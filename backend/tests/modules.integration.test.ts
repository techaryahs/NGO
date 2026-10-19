import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { buildApp } from '../src/app.js';
import { config } from '../src/config/index.js';
import { pool, query } from '../src/db/index.js';
import { runMigrations } from '../src/db/migrate.js';
import { installTestFirebaseKeys, signedTestToken } from './helpers/auth.js';

// Explicit opt-in, dedicated database, local address and PostgreSQL-major guards
// run before migrations or data writes. This suite never truncates a table.
describe.runIf(process.env.AUDIT_DATABASE_TESTS === '1')('Modules: real PostgreSQL API integration', () => {
  const app = buildApp({ logger: false });
  const prefix = 'mod_audit_';
  const patientId = `${prefix}patient`;
  const auth = (role = 'staff') => ({ authorization: `Bearer ${signedTestToken(`test-uid-${role}`)}` });
  const request = (method: 'GET' | 'POST' | 'PUT' | 'DELETE', url: string, payload?: unknown, role = 'staff') =>
    app.inject({ method, url, headers: { ...auth(role), ...(payload === undefined ? {} : { 'content-type': 'application/json' }) },
      ...(payload === undefined ? {} : { payload: JSON.stringify(payload) }) });

  beforeAll(async () => {
    const target = new URL(config.getEffectiveDatabaseUrl());
    expect(['127.0.0.1', 'localhost']).toContain(target.hostname);
    expect(target.port).toBe('55439');
    expect(target.pathname).toBe('/ngo_audit_modules');
    const identity = await query('SELECT current_database() AS db, host(inet_server_addr()) AS host, current_setting(\'server_version_num\')::int AS version');
    expect(identity.rows[0].db).toBe('ngo_audit_modules');
    expect(['127.0.0.1', '::1']).toContain(identity.rows[0].host);
    expect(identity.rows[0].version).toBeGreaterThanOrEqual(160000);
    expect(identity.rows[0].version).toBeLessThan(170000);
    await runMigrations('up');
    // Reruns remove only this suite's synthetic rows, after all target guards.
    for (const [table, column] of [
      ['patient_photos', 'patient_id'], ['attendance_records', 'patient_id'], ['sponsorships', 'id'],
      ['purchases', 'id'], ['expense_entries', 'id'], ['salaries', 'id'], ['patients', 'id'],
      ['inventory_items', 'id'], ['vendors', 'id'], ['system_counters', 'counter_name'], ['system_settings', 'category'],
    ]) await query(`DELETE FROM ${table} WHERE starts_with(${column}, $1)`, [prefix]);
    for (const role of ['admin', 'staff', 'volunteer']) {
      await query(`INSERT INTO users(id, email, name, role) VALUES($1, $2, $3, $4)
        ON CONFLICT (id) DO UPDATE SET role = EXCLUDED.role`, [`test-uid-${role}`, `test-uid-${role}@ngo.test`, `Synthetic ${role}`, role]);
    }
    await query(`INSERT INTO patients(id, full_name, date_of_birth, gender, contact_number, emergency_contact,
      emergency_contact_name, medical_condition, admission_date, created_by)
      VALUES($1,'Synthetic module audit','1990-01-01','other','0000000000','0000000000','Synthetic contact','test','2026-10-01','test-uid-staff')
      ON CONFLICT (id) DO NOTHING`, [patientId]);
    await app.ready();
  });

  beforeEach(() => {
    vi.restoreAllMocks();
    installTestFirebaseKeys();
  });

  afterAll(async () => {
    await app.close();
    await pool.end();
  });

  it('rejects unauthenticated requests across module families', async () => {
    for (const url of ['/api/attendance', '/api/counters/registrationNumber', '/api/settings/security', '/api/photos/missing/patient', '/api/erp/inventory']) {
      expect((await app.inject({ method: 'GET', url })).statusCode).toBe(401);
    }
  });

  it('enforces Firebase-equivalent roles for sensitive reads and module writes', async () => {
    for (const url of ['/api/attendance', '/api/counters/registrationNumber', '/api/settings/security', `/api/photos/${patientId}/patient`]) {
      expect((await request('GET', url, undefined, 'volunteer')).statusCode).toBe(403);
    }
    for (const [url, payload] of [
      ['/api/erp/inventory', { name: 'Forbidden item' }],
      ['/api/erp/vendors', { name: 'Forbidden vendor' }],
      ['/api/erp/purchases', {}], ['/api/erp/expenses', {}], ['/api/erp/sponsorships', {}],
      ['/api/attendance', { date: '2026-10-01', patientId, payload: {} }],
      ['/api/counters/registrationNumber/next', {}],
    ] as const) {
      expect((await request('POST', url, payload, 'volunteer')).statusCode).toBe(403);
    }
    expect((await request('PUT', '/api/settings/security/locked', true, 'staff')).statusCode).toBe(403);
    expect((await request('GET', '/api/erp/inventory', undefined, 'volunteer')).statusCode).toBe(200);
  });

  it('upserts patient attendance, survives a repeated request, and persists the latest payload', async () => {
    const body = { date: '2026-10-02', patientId, payload: { status: 'present', note: 'Synthetic' } };
    expect((await request('POST', '/api/attendance', body)).statusCode).toBe(200);
    expect((await request('POST', '/api/attendance', body)).statusCode).toBe(200);
    expect((await request('POST', '/api/attendance', { ...body, payload: { status: 'absent' } })).statusCode).toBe(200);
    const stored = await query('SELECT * FROM attendance_records WHERE id=$1', [`attendance/${body.date}/${patientId}`]);
    expect(stored.rowCount).toBe(1);
    expect(stored.rows[0].payload).toEqual({ status: 'absent' });
    const array = await request('GET', `/api/attendance?date=${body.date}&patientId=${patientId}`);
    expect(array.json()).toEqual([expect.objectContaining({ date: body.date, patientId, payload: { status: 'absent' } })]);
    const map = await request('GET', `/api/attendance?date=${body.date}&kind=attendance&format=map`);
    expect(map.json()[patientId]).toEqual({ status: 'absent' });
  });

  it('preserves attendant attendance independently of patient attendance', async () => {
    const body = { date: '2026-10-02', patientId, kind: 'attendant_attendance', payload: { att_1: { status: 'present' } } };
    expect((await request('POST', '/api/attendance', body)).statusCode).toBe(200);
    const stored = await query('SELECT kind,payload FROM attendance_records WHERE patient_id=$1 AND attendance_date=$2 ORDER BY kind', [patientId, body.date]);
    expect(stored.rows).toEqual([
      { kind: 'attendance', payload: { status: 'absent' } },
      { kind: 'attendant_attendance', payload: body.payload },
    ]);
    expect((await request('GET', `/api/attendance?date=${body.date}&format=map`)).json()[patientId]).toEqual({ status: 'absent' });
  });

  it.each(['2026-02-30', 'invalid', '2026-1-1'])('rejects invalid attendance date %s before writing', async (date) => {
    const response = await request('POST', '/api/attendance', { date, patientId, payload: {} });
    expect(response.statusCode).toBe(400);
  });

  it('rejects malformed attendance input and invalid filters without a database 500', async () => {
    expect((await request('POST', '/api/attendance', {})).statusCode).toBe(400);
    expect((await request('POST', '/api/attendance', { date: '2026-10-03', patientId, kind: 'unknown', payload: {} })).statusCode).toBe(400);
    expect((await request('GET', '/api/attendance?date=invalid')).statusCode).toBe(400);
    expect((await request('POST', '/api/attendance', { date: '2026-10-03', patientId: `${prefix}missing`, payload: {} })).statusCode).toBe(409);
  });

  it('rolls back a bulk attendance update when a later patient reference is invalid', async () => {
    const date = '2026-10-04';
    expect((await request('POST', '/api/attendance', { date, patientId, payload: { status: 'absent' } })).statusCode).toBe(200);
    const response = await request('POST', '/api/attendance/bulk', { date, records: {
      [patientId]: { status: 'present' }, [`${prefix}missing`]: { status: 'present' },
    } });
    expect(response.statusCode).toBe(409);
    expect(response.body).not.toMatch(/violates|attendance_records_patient_id_fkey|Key \(/i);
    const stored = await query('SELECT payload FROM attendance_records WHERE attendance_date=$1 AND patient_id=$2', [date, patientId]);
    expect(stored.rows).toEqual([{ payload: { status: 'absent' } }]);
    expect((await query('SELECT count(*)::int AS count FROM attendance_records WHERE patient_id=$1', [`${prefix}missing`])).rows[0].count).toBe(0);
  });

  it('commits valid bulk attendance records and repeats without duplicating', async () => {
    const body = { date: '2026-10-05', records: { [patientId]: { status: 'present' } } };
    for (let i = 0; i < 2; i++) expect((await request('POST', '/api/attendance/bulk', body)).json().count).toBe(1);
    expect((await query('SELECT count(*)::int AS count FROM attendance_records WHERE attendance_date=$1 AND patient_id=$2', [body.date, patientId])).rows[0].count).toBe(1);
  });

  it('preserves every attendance date in map history instead of overwriting the same patient', async () => {
    const response = await request('GET', `/api/attendance?kind=attendance&patientId=${patientId}&format=map`);
    expect(response.json()).toMatchObject({
      '2026-10-02': { [patientId]: { status: 'absent' } },
      '2026-10-04': { [patientId]: { status: 'absent' } },
      '2026-10-05': { [patientId]: { status: 'present' } },
    });
  });

  it('allocates two concurrent registration values atomically', async () => {
    const name = `${prefix}registration`;
    await query('DELETE FROM system_counters WHERE counter_name=$1', [name]);
    const results = await Promise.all([request('POST', `/api/counters/${name}/next`, {}), request('POST', `/api/counters/${name}/next`, {})]);
    expect(results.map((r) => r.statusCode)).toEqual([200, 200]);
    expect(results.map((r) => r.json().nextValue).sort()).toEqual([1, 2]);
    expect((await request('GET', `/api/counters/${name}`)).json().currentValue).toBe(2);
    expect((await query('SELECT current_value::text AS value FROM system_counters WHERE counter_name=$1', [name])).rows[0].value).toBe('2');
  });

  it('validates counter reset input and denies untrusted counter changes', async () => {
    const url = `/api/counters/${prefix}reset`;
    for (const value of [-1, 1.5, 'not-a-number', 9007199254740992]) expect((await request('PUT', url, { value })).statusCode).toBe(400);
    expect((await request('PUT', url, { value: 20 }, 'volunteer')).statusCode).toBe(403);
    expect((await request('PUT', url, { value: 20 })).json().currentValue).toBe(20);
  });

  it('bootstraps registration allocation above imported patient registrations', async () => {
    await query('DELETE FROM system_counters WHERE counter_name=$1', ['registrationNumber']);
    await query('UPDATE patients SET registration_number=$1 WHERE id=$2', ['1042', patientId]);
    const responses = await Promise.all([
      request('POST', '/api/counters/registrationNumber/next', {}),
      request('POST', '/api/counters/registrationNumber/next', {}),
    ]);
    expect(responses.map((response) => response.json().nextValue).sort()).toEqual([1043, 1044]);
    expect((await query('SELECT registration_number FROM patients WHERE id=$1', [patientId])).rows[0].registration_number).toBe('1042');
  });

  it('rejects counter exhaustion without rounding or incrementing beyond the safe range', async () => {
    const name = `${prefix}exhausted`;
    expect((await request('PUT', `/api/counters/${name}`, { value: Number.MAX_SAFE_INTEGER })).statusCode).toBe(200);
    expect((await request('POST', `/api/counters/${name}/next`, {})).statusCode).toBe(409);
    expect((await query('SELECT current_value::text AS value FROM system_counters WHERE counter_name=$1', [name])).rows[0].value).toBe('9007199254740991');
  });

  it('stores false and zero setting values without replacing them with empty objects', async () => {
    expect((await request('PUT', `/api/settings/${prefix}config/disabled`, false, 'admin')).json()).toBe(false);
    expect((await request('PUT', `/api/settings/${prefix}config/zero`, 0, 'admin')).json()).toBe(0);
    expect((await request('GET', `/api/settings/${prefix}config`)).json()).toEqual({ disabled: false, zero: 0 });
    expect((await request('GET', `/api/settings/${prefix}config/disabled`)).json()).toBe(false);
    expect((await request('GET', `/api/settings/${prefix}config/missing`)).json()).toEqual({});
    expect((await query('SELECT settings_value FROM system_settings WHERE category=$1 ORDER BY settings_key', [`${prefix}config`])).rows).toEqual([{ settings_value: false }, { settings_value: 0 }]);
  });

  it('supports category settings writes used by pricing and security clients', async () => {
    const url = `/api/settings/${prefix}pricing`;
    expect((await request('PUT', url, { dailyRate: 200, locked: false }, 'admin')).statusCode).toBe(200);
    expect((await request('PUT', url, { dailyRate: 250 }, 'admin')).statusCode).toBe(200);
    expect((await request('GET', url)).json()).toEqual({ dailyRate: 250, locked: false });
    expect((await request('PUT', url, { dailyRate: 300 }, 'staff')).statusCode).toBe(403);
  });

  it('stores and retrieves microsecond photo versions written by the Dart photo service', async () => {
    const version = 1770000000000000;
    const url = `/api/photos/${patientId}/patient`;
    expect((await request('PUT', url, { data: 'aGVsbG8=', contentType: 'image/png', version })).statusCode).toBe(200);
    const saved = await request('GET', url);
    expect(saved.json()).toMatchObject({ patientId, photoType: 'patient', contentType: 'image/png', data: 'aGVsbG8=', version });
    expect((await query('SELECT version::text AS version FROM patient_photos WHERE patient_id=$1', [patientId])).rows[0].version).toBe(String(version));
  });

  it('stores attendant photos with their patient relationship', async () => {
    const url = `/api/photos/${patientId}/attendants/att_1`;
    expect((await request('PUT', url, { data: 'aGVsbG8=', version: 10 })).statusCode).toBe(200);
    expect((await request('GET', url)).json()).toMatchObject({ patientId, photoType: 'attendant', data: 'aGVsbG8=' });
  });

  it('rejects photo path/body mismatches, invalid references, and invalid image metadata', async () => {
    const url = `/api/photos/${patientId}/patient`;
    expect((await request('PUT', url, { data: 'aGVsbG8=', patientId: `${prefix}other` })).statusCode).toBe(400);
    expect((await request('PUT', '/api/photos/invalid', { data: 'aGVsbG8=' })).statusCode).toBe(400);
    expect((await request('PUT', url, { data: 'aGVsbG8=', contentType: 'text/html' })).statusCode).toBe(400);
    expect((await request('PUT', url, { data: '!', version: -1 })).statusCode).toBe(400);
    expect((await request('PUT', `/api/photos/${prefix}missing/patient`, { data: 'aGVsbG8=' })).statusCode).toBe(409);
    expect((await request('GET', `/api/photos/${prefix}missing/patient`)).statusCode).toBe(404);
  });

  it('rejects stale photo writes without replacing the newer data', async () => {
    const url = `/api/photos/${patientId}/attendants/concurrent`;
    const write = { data: 'bmV3', contentType: 'image/jpeg', version: 20 };
    expect((await request('PUT', url, write)).statusCode).toBe(200);
    expect((await request('PUT', url, write)).statusCode).toBe(200);
    expect((await request('PUT', url, { ...write, data: 'b2xk', version: 19 })).statusCode).toBe(409);
    expect((await request('GET', url)).json().data).toBe(write.data);
  });

  it('creates inventory/vendors and persists their values and authoritative creator', async () => {
    const inventory = await request('POST', '/api/erp/inventory', { id: `${prefix}inventory`, name: 'Synthetic rice', minStockLevel: 2, currentStock: 8, createdBy: 'forged-admin' });
    expect(inventory.statusCode).toBe(201);
    expect((await query('SELECT current_stock, min_stock_level, created_by FROM inventory_items WHERE id=$1', [`${prefix}inventory`])).rows[0]).toEqual({ current_stock: 8, min_stock_level: 2, created_by: 'test-uid-staff' });
    const vendor = await request('POST', '/api/erp/vendors', { id: `${prefix}vendor`, name: 'Synthetic supplier', contactPerson: 'Synthetic contact', email: '' });
    expect(vendor.statusCode).toBe(201);
    expect((await request('GET', '/api/erp/inventory')).json()).toEqual(expect.arrayContaining([expect.objectContaining({ id: `${prefix}inventory` })]));
    expect((await request('GET', '/api/erp/vendors')).json()).toEqual(expect.arrayContaining([expect.objectContaining({ id: `${prefix}vendor` })]));
  });

  it('creates purchases with exact decimals and rejects invalid foreign keys atomically', async () => {
    const body = { id: `${prefix}purchase`, vendorId: `${prefix}vendor`, vendorName: 'Synthetic supplier', itemId: `${prefix}inventory`, itemName: 'Synthetic rice', quantity: 3, unitPrice: '0.10', totalAmount: '0.30', purchaseDate: '2026-10-02' };
    expect((await request('POST', '/api/erp/purchases', body)).statusCode).toBe(201);
    expect((await query('SELECT vendor_id,item_id,unit_price::text,total_amount::text FROM purchases WHERE id=$1', [body.id])).rows[0]).toEqual({ vendor_id: body.vendorId, item_id: body.itemId, unit_price: '0.10', total_amount: '0.30' });
    expect((await request('POST', '/api/erp/purchases', { ...body, id: `${prefix}bad_purchase`, itemId: `${prefix}missing` })).statusCode).toBe(409);
    expect((await query('SELECT count(*)::int AS count FROM purchases WHERE id=$1', [`${prefix}bad_purchase`])).rows[0].count).toBe(0);
    expect((await request('GET', '/api/erp/purchases')).json()).toEqual(expect.arrayContaining([expect.objectContaining({ id: body.id, total_amount: '0.30' })]));
  });

  it('rejects ERP malformed input, duplicate IDs and invalid decimals without 500 errors', async () => {
    expect((await request('POST', '/api/erp/inventory', {})).statusCode).toBe(400);
    expect((await request('POST', '/api/erp/vendors', {})).statusCode).toBe(400);
    expect((await request('POST', '/api/erp/inventory', { id: `${prefix}inventory`, name: 'Duplicate' })).statusCode).toBe(409);
    expect((await request('POST', '/api/erp/purchases', { quantity: -1 })).statusCode).toBe(400);
    expect((await request('POST', '/api/erp/expenses', { amount: 'NaN' })).statusCode).toBe(400);
    expect((await request('POST', '/api/erp/expenses', { amount: '0.001' })).statusCode).toBe(400);
    expect((await request('POST', '/api/erp/sponsorships', { amount: 2, sponsorshipDate: 'invalid' })).statusCode).toBe(400);
  });

  it('stores expenses, sponsorship patient relationships and reads supported financial lists', async () => {
    const expense = { id: `${prefix}expense`, amount: '12.34', paidTo: 'Synthetic shop', expenseDate: '2026-10-02' };
    expect((await request('POST', '/api/erp/expenses', expense)).statusCode).toBe(201);
    expect((await query('SELECT amount::text FROM expense_entries WHERE id=$1', [expense.id])).rows[0].amount).toBe('12.34');
    const sponsorship = { id: `${prefix}sponsorship`, sponsorName: 'Synthetic sponsor', patientId, amount: '30.10', sponsorshipDate: '2026-10-02' };
    expect((await request('POST', '/api/erp/sponsorships', sponsorship)).statusCode).toBe(201);
    expect((await query('SELECT patient_id,amount::text FROM sponsorships WHERE id=$1', [sponsorship.id])).rows[0]).toEqual({ patient_id: patientId, amount: '30.10' });
    expect((await request('POST', '/api/erp/sponsorships', { ...sponsorship, id: `${prefix}bad_sponsorship`, patientId: `${prefix}missing` })).statusCode).toBe(409);
    expect((await request('GET', '/api/erp/expenses')).json()).toEqual(expect.arrayContaining([expect.objectContaining({ id: expense.id, amount: '12.34' })]));
    expect((await request('GET', '/api/erp/sponsorships')).json()).toEqual(expect.arrayContaining([expect.objectContaining({ id: sponsorship.id, patient_id: patientId, amount: '30.10' })]));
  });

  it('retrieves an existing salary row through the supported list operation', async () => {
    const salaryId = `${prefix}salary`;
    await query(`INSERT INTO salaries(id,staff_id,staff_name,month,year,base_salary,deductions,bonuses,net_salary)
      VALUES($1,'test-uid-staff','Synthetic employee',10,2026,'100.10','0.10','0.20','100.20')`, [salaryId]);
    expect((await request('GET', '/api/erp/salaries')).json()).toEqual(expect.arrayContaining([
      expect.objectContaining({ id: salaryId, staff_id: 'test-uid-staff', net_salary: '100.20', month: 10, year: 2026 }),
    ]));
  });

  it.each([
    {
      module: 'inventory', table: 'inventory_items',
      create: { name: 'Synthetic editable inventory', currentStock: 8, minStockLevel: 2 },
      update: { name: 'Synthetic updated inventory', currentStock: 0, minStockLevel: 0 },
      invalid: { currentStock: -1 },
      expected: { name: 'Synthetic updated inventory', current_stock: 0, min_stock_level: 0, created_by: 'test-uid-staff', updated_by: 'test-uid-staff' },
    },
    {
      module: 'vendors', table: 'vendors',
      create: { name: 'Synthetic editable vendor', phone: '000', contactPerson: 'Synthetic contact' },
      update: { name: 'Synthetic updated vendor', phone: '' },
      invalid: { email: 'invalid-email' },
      expected: { name: 'Synthetic updated vendor', phone: '', contact_person: 'Synthetic contact' },
    },
    {
      module: 'purchases', table: 'purchases',
      create: { vendorName: 'Synthetic supplier', itemName: 'Synthetic item', quantity: 2, unitPrice: '0.10', totalAmount: '0.20' },
      update: { quantity: 3, unitPrice: '0.00', totalAmount: '0.00' },
      invalid: { totalAmount: '0.001' },
      expected: { vendor_name: 'Synthetic supplier', item_name: 'Synthetic item', quantity: 3, unit_price: '0.00', total_amount: '0.00' },
    },
    {
      module: 'expenses', table: 'expense_entries',
      create: { amount: '1.23', paidTo: 'Synthetic shop', description: 'Synthetic original note' },
      update: { amount: '0.00', description: 'Synthetic edited note' },
      invalid: { amount: '-1' },
      expected: { amount: '0.00', paid_to: 'Synthetic shop', description: 'Synthetic edited note' },
    },
    {
      module: 'sponsorships', table: 'sponsorships',
      create: { sponsorName: 'Synthetic original sponsor', patientId, amount: '1.23', notes: 'Synthetic retained note' },
      update: { sponsorName: 'Synthetic updated sponsor', amount: '0.00' },
      invalid: { amount: 'NaN' },
      expected: { sponsor_name: 'Synthetic updated sponsor', patient_id: patientId, amount: '0.00', notes: 'Synthetic retained note' },
    },
  ])('edits and deletes an existing $module record with role, validation and persisted-state checks', async ({ module, table, create, update, invalid, expected }) => {
    const recordId = `${prefix}crud_${module}`;
    const url = `/api/erp/${module}/${recordId}`;
    const created = await request('POST', `/api/erp/${module}`, { id: recordId, ...create });
    expect(created.statusCode).toBe(201);
    const original = (await query(`SELECT * FROM ${table} WHERE id=$1`, [recordId])).rows[0];

    expect((await request('PUT', url, update, 'volunteer')).statusCode).toBe(403);
    expect((await request('DELETE', url, undefined, 'volunteer')).statusCode).toBe(403);
    expect((await request('PUT', url, invalid)).statusCode).toBe(400);
    expect((await query(`SELECT * FROM ${table} WHERE id=$1`, [recordId])).rows[0]).toEqual(original);

    const edited = await request('PUT', url, update);
    expect(edited.statusCode).toBe(200);
    expect(edited.json()).toMatchObject({ id: recordId, ...expected });
    expect((await query(`SELECT * FROM ${table} WHERE id=$1`, [recordId])).rows[0]).toMatchObject(expected);
    expect((await request('GET', `/api/erp/${module}`)).json()).toEqual(expect.arrayContaining([
      expect.objectContaining({ id: recordId, ...expected }),
    ]));

    const deleted = await request('DELETE', url);
    expect(deleted.statusCode).toBe(200);
    expect(deleted.json()).toMatchObject({ success: true, deletedId: recordId });
    expect((await query(`SELECT * FROM ${table} WHERE id=$1`, [recordId])).rowCount).toBe(0);
    expect((await request('DELETE', url)).statusCode).toBe(404);
  });

  it('adjusts stock for purchase creation, quantity changes, item moves, detachment and deletion', async () => {
    const first = `${prefix}stock_first`;
    const second = `${prefix}stock_second`;
    const purchaseId = `${prefix}stock_lifecycle`;
    for (const [id, currentStock] of [[first, 10], [second, 4]] as const) {
      expect((await request('POST', '/api/erp/inventory', { id, name: id, currentStock })).statusCode).toBe(201);
    }
    const stocks = async () => (await query('SELECT id,current_stock FROM inventory_items WHERE id=ANY($1::text[]) ORDER BY id', [[first, second]])).rows.map(row => row.current_stock);
    expect((await request('POST', '/api/erp/purchases', { id: purchaseId, vendorName: 'Synthetic supplier', itemId: first, itemName: 'Synthetic first item', quantity: 3, unitPrice: '0.10', totalAmount: '0.30' })).statusCode).toBe(201);
    expect(await stocks()).toEqual([13, 4]);
    expect((await request('GET', `/api/erp/inventory/${first}`)).json()).toMatchObject({ id: first, current_stock: 13 });
    expect((await request('PUT', `/api/erp/purchases/${purchaseId}`, { quantity: 5 })).statusCode).toBe(200);
    expect(await stocks()).toEqual([15, 4]);
    expect((await request('PUT', `/api/erp/purchases/${purchaseId}`, { itemId: second, quantity: 2 })).statusCode).toBe(200);
    expect(await stocks()).toEqual([10, 6]);
    expect((await request('PUT', `/api/erp/purchases/${purchaseId}`, { itemId: null })).statusCode).toBe(200);
    expect(await stocks()).toEqual([10, 4]);
    expect((await request('PUT', `/api/erp/purchases/${purchaseId}`, { itemId: first, quantity: 1 })).statusCode).toBe(200);
    expect(await stocks()).toEqual([11, 4]);
    expect((await request('DELETE', `/api/erp/purchases/${purchaseId}`)).statusCode).toBe(200);
    expect((await request('DELETE', `/api/erp/purchases/${purchaseId}`)).statusCode).toBe(404);
    expect(await stocks()).toEqual([10, 4]);
  });

  it('serializes concurrent purchase increments and opposite item moves without losing stock', async () => {
    const first = `${prefix}stock_race_first`;
    const second = `${prefix}stock_race_second`;
    for (const itemId of [first, second]) expect((await request('POST', '/api/erp/inventory', { id: itemId, name: itemId, currentStock: 0 })).statusCode).toBe(201);
    const base = { vendorName: 'Synthetic supplier', itemId: first, itemName: 'Synthetic item', quantity: 0.25, unitPrice: '1.00', totalAmount: '0.25' };
    const created = await Promise.all(Array.from({ length: 10 }, (_, index) => request('POST', '/api/erp/purchases', { id: `${prefix}stock_race_${index}`, ...base })));
    expect(created.map(response => response.statusCode)).toEqual(Array(10).fill(201));
    expect((await request('GET', `/api/erp/inventory/${first}`)).json().current_stock).toBe(2.5);
    expect((await request('POST', '/api/erp/purchases', { id: `${prefix}stock_race_0`, ...base })).statusCode).toBe(409);
    expect((await request('GET', `/api/erp/inventory/${first}`)).json().current_stock).toBe(2.5);

    const firstPurchase = `${prefix}stock_swap_first`;
    const secondPurchase = `${prefix}stock_swap_second`;
    expect((await request('POST', '/api/erp/purchases', { id: firstPurchase, ...base, quantity: 2 })).statusCode).toBe(201);
    expect((await request('POST', '/api/erp/purchases', { id: secondPurchase, ...base, itemId: second, quantity: 3 })).statusCode).toBe(201);
    const moved = await Promise.all([
      request('PUT', `/api/erp/purchases/${firstPurchase}`, { itemId: second }),
      request('PUT', `/api/erp/purchases/${secondPurchase}`, { itemId: first }),
    ]);
    expect(moved.map(response => response.statusCode)).toEqual([200, 200]);
    expect((await query('SELECT current_stock FROM inventory_items WHERE id=ANY($1::text[]) ORDER BY id', [[first, second]])).rows.map(row => row.current_stock)).toEqual([5.5, 2]);

    const edits = await Promise.all([
      request('PUT', `/api/erp/purchases/${firstPurchase}`, { quantity: 4 }),
      request('PUT', `/api/erp/purchases/${firstPurchase}`, { quantity: 5 }),
    ]);
    expect(edits.map(response => response.statusCode)).toEqual([200, 200]);
    const finalQuantity = (await query('SELECT quantity FROM purchases WHERE id=$1', [firstPurchase])).rows[0].quantity;
    expect((await request('GET', `/api/erp/inventory/${second}`)).json().current_stock).toBe(finalQuantity);
  });

  it('rolls back both purchase and stock on create, edit and delete failures and preserves the zero-stock clamp', async () => {
    const itemId = `${prefix}stock_rollback`;
    const purchaseId = `${prefix}stock_rollback_purchase`;
    const base = { vendorName: 'Synthetic supplier', itemId, itemName: 'Synthetic item', quantity: 2, unitPrice: '1.00', totalAmount: '2.00' };
    expect((await request('POST', '/api/erp/inventory', { id: itemId, name: itemId, currentStock: 10 })).statusCode).toBe(201);
    expect((await request('POST', '/api/erp/purchases', { id: purchaseId, ...base })).statusCode).toBe(201);
    await query(`CREATE FUNCTION mod_audit_fail_stock() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
      IF NEW.id = 'mod_audit_stock_rollback' THEN RAISE EXCEPTION 'synthetic stock failure'; END IF;
      RETURN NEW; END $$;
      CREATE TRIGGER mod_audit_fail_stock BEFORE UPDATE ON inventory_items FOR EACH ROW EXECUTE FUNCTION mod_audit_fail_stock()`);
    try {
      expect((await request('POST', '/api/erp/purchases', { id: `${prefix}stock_failed`, ...base })).statusCode).toBe(500);
      expect((await query('SELECT id FROM purchases WHERE id=$1', [`${prefix}stock_failed`])).rowCount).toBe(0);
      expect((await request('PUT', `/api/erp/purchases/${purchaseId}`, { quantity: 4 })).statusCode).toBe(500);
      expect((await request('DELETE', `/api/erp/purchases/${purchaseId}`)).statusCode).toBe(500);
      expect((await query('SELECT quantity FROM purchases WHERE id=$1', [purchaseId])).rows[0].quantity).toBe(2);
      expect((await query('SELECT current_stock FROM inventory_items WHERE id=$1', [itemId])).rows[0].current_stock).toBe(12);
    } finally {
      await query('DROP TRIGGER mod_audit_fail_stock ON inventory_items; DROP FUNCTION mod_audit_fail_stock()');
    }
    expect((await request('PUT', `/api/erp/inventory/${itemId}`, { currentStock: 0 })).statusCode).toBe(200);
    expect((await request('DELETE', `/api/erp/purchases/${purchaseId}`)).statusCode).toBe(200);
    expect((await query('SELECT current_stock FROM inventory_items WHERE id=$1', [itemId])).rows[0].current_stock).toBe(0);
  });

  it.each([
    { module: 'vendors', payload: { name: 'Synthetic form vendor', contactPerson: 'Synthetic contact', phone: '000', email: '', gstNumber: 'SYN-GST', notes: 'Supplier note' }, expected: { gstNumber: 'SYN-GST', notes: 'Supplier note' }, edit: { gstNumber: '', notes: '' }, edited: { gstNumber: '', notes: '' } },
    { module: 'purchases', payload: { vendorName: 'Synthetic form vendor', itemName: 'Synthetic form item', quantity: 1, unitPrice: 0, totalAmount: 0, paymentDetails: { paymentMethod: 'UPI', paymentStatus: 'Partial', paymentDate: 0, transactionId: 'SYN-TX', proofUrl: null } }, expected: { paymentDetails: { paymentMethod: 'UPI', paymentStatus: 'Partial', paymentDate: 0, transactionId: 'SYN-TX', proofUrl: null } }, edit: { notes: 'Edited while retaining payment details' }, edited: { paymentDetails: { paymentMethod: 'UPI', paymentStatus: 'Partial', paymentDate: 0, transactionId: 'SYN-TX', proofUrl: null } } },
    { module: 'expenses', payload: { amount: 0, paidTo: 'Synthetic shop', category: 'Medical', subcategory: 'Supplies', itemName: 'Synthetic gauze', vendorId: null, quantity: 0, unit: 'box', unitPrice: 0, paymentDetails: { paymentMethod: 'Cash', paymentStatus: 'Paid', cashVoucherNumber: 'SYN-V', chequeDate: null } }, expected: { subcategory: 'Supplies', itemName: 'Synthetic gauze', vendorId: null, quantity: 0, unit: 'box', unitPrice: 0, paymentDetails: { cashVoucherNumber: 'SYN-V', chequeDate: null } }, edit: { subcategory: null, quantity: null }, edited: { subcategory: null, quantity: null, itemName: 'Synthetic gauze', paymentDetails: { cashVoucherNumber: 'SYN-V', chequeDate: null } } },
    { module: 'sponsorships', payload: { sponsorName: 'Synthetic form sponsor', sponsorPrefix: 'Smt', sponsorMobile: '000', referencePrefix: 'Dr', referenceName: 'Synthetic reference', referenceMobile: '001', occasion: 'Anniversary', honoreeName: 'Synthetic honoree', amount: 0, paymentMethod: 'UPI', paymentStatus: 'Partial', transactionRef: 'SYN-SP', bookingStatus: 'Confirmed', notes: '' }, expected: { sponsorPrefix: 'Smt', sponsorMobile: '000', referencePrefix: 'Dr', referenceName: 'Synthetic reference', referenceMobile: '001', occasion: 'Anniversary', honoreeName: 'Synthetic honoree', paymentStatus: 'Partial', transactionRef: 'SYN-SP', bookingStatus: 'Confirmed' }, edit: { honoreeName: null, sponsorMobile: '', paymentStatus: 'Paid', bookingStatus: 'Cancelled' }, edited: { honoreeName: null, sponsorMobile: '', paymentStatus: 'Paid', bookingStatus: 'Cancelled', referenceName: 'Synthetic reference', transactionRef: 'SYN-SP' } },
  ])('round-trips actual Flutter $module form metadata with authoritative audit identity', async ({ module, payload, expected, edit, edited }) => {
    const recordId = `${prefix}form_${module}`;
    const created = await request('POST', `/api/erp/${module}`, { id: recordId, ...payload, createdBy: 'forged', updatedBy: 'forged', createdAt: 0, updatedAt: 0, details: { role: 'admin' } });
    expect(created.statusCode).toBe(201);
    expect(created.json()).toMatchObject({ id: recordId, ...expected, createdBy: 'test-uid-staff', updatedBy: 'test-uid-staff' });
    expect(created.json().createdAt).toBeGreaterThan(0);
    expect(created.json().role).toBeUndefined();
    const saved = (await request('GET', `/api/erp/${module}`)).json().find((row: any) => row.id === recordId);
    expect(saved).toMatchObject(expected);
    expect((await request('PUT', `/api/erp/${module}/${recordId}`, { ...edit, createdBy: 'forged-rewrite' }, 'admin')).statusCode).toBe(200);
    const updated = (await request('GET', `/api/erp/${module}`)).json().find((row: any) => row.id === recordId);
    expect(updated).toMatchObject({ ...edited, createdBy: 'test-uid-staff', updatedBy: 'test-uid-admin' });
    expect((await request('DELETE', `/api/erp/${module}/${recordId}`)).statusCode).toBe(200);
  });

  it('supports admin-only salary form CRUD, exact net calculation and nested payment metadata', async () => {
    const recordId = `${prefix}form_salary`;
    const payload = { id: recordId, employeeName: 'Synthetic employee', role: 'Staff', salaryMonth: 'October 2026', grossSalary: 100.10, deductions: 0.10, netSalary: 100, paymentDetails: { paymentMethod: 'Bank Transfer', paymentStatus: 'Paid', paymentDate: 0, bankName: 'Synthetic bank', transactionId: 'SYN-SAL', chequeDate: null }, createdBy: 'forged', updatedBy: 'forged' };
    expect((await request('POST', '/api/erp/salaries', payload, 'staff')).statusCode).toBe(403);
    expect((await request('POST', '/api/erp/salaries', payload, 'volunteer')).statusCode).toBe(403);
    const created = await request('POST', '/api/erp/salaries', payload, 'admin');
    expect(created.statusCode).toBe(201);
    expect(created.json()).toMatchObject({ employeeName: payload.employeeName, role: 'Staff', salaryMonth: 'October 2026', grossSalary: '100.10', deductions: '0.10', netSalary: '100.00', createdBy: 'test-uid-admin', paymentDetails: payload.paymentDetails });
    expect((await request('PUT', `/api/erp/salaries/${recordId}`, { grossSalary: 200 }, 'staff')).statusCode).toBe(403);
    expect((await request('DELETE', `/api/erp/salaries/${recordId}`, undefined, 'staff')).statusCode).toBe(403);
    expect((await request('PUT', `/api/erp/salaries/${recordId}`, { grossSalary: 0, deductions: 0, netSalary: 0 }, 'admin')).statusCode).toBe(200);
    const saved = (await request('GET', '/api/erp/salaries')).json().find((row: any) => row.id === recordId);
    expect(saved).toMatchObject({ grossSalary: '0.00', deductions: '0.00', netSalary: '0.00', salaryMonth: 'October 2026', paymentDetails: payload.paymentDetails });
    for (const invalid of [{ salaryMonth: 'not a month' }, { grossSalary: 10, deductions: 11 }, { grossSalary: 10, deductions: 0, netSalary: 11 }]) expect((await request('PUT', `/api/erp/salaries/${recordId}`, invalid, 'admin')).statusCode).toBe(400);
    expect((await request('DELETE', `/api/erp/salaries/${recordId}`, undefined, 'admin')).statusCode).toBe(200);
    expect((await request('DELETE', `/api/erp/salaries/${recordId}`, undefined, 'admin')).statusCode).toBe(404);
  });

  it('rejects invalid ERP form metadata before writes rather than silently stripping it', async () => {
    const recordId = `${prefix}form_invalid`;
    expect((await request('POST', '/api/erp/sponsorships', { id: recordId, sponsorName: 'Synthetic invalid', amount: 1, bookingStatus: 'invented' })).statusCode).toBe(400);
    expect((await request('POST', '/api/erp/expenses', { id: recordId, amount: 1, paymentDetails: { paymentMethod: 'Cash', paymentStatus: 'Paid', role: 'admin' } })).statusCode).toBe(400);
    expect((await query('SELECT id FROM sponsorships WHERE id=$1', [recordId])).rowCount).toBe(0);
    expect((await query('SELECT id FROM expense_entries WHERE id=$1', [recordId])).rowCount).toBe(0);
  });

  it('returns 404 for missing ERP records and absent single-record read routes', async () => {
    for (const module of ['inventory', 'vendors', 'purchases', 'expenses', 'salaries', 'sponsorships']) {
      expect((await request('PUT', `/api/erp/${module}/missing`, {}, module === 'salaries' ? 'admin' : 'staff')).statusCode).toBe(404);
      expect((await request('GET', `/api/erp/${module}/missing`)).statusCode).toBe(404);
      expect((await request('DELETE', `/api/erp/${module}/missing`, undefined, module === 'salaries' ? 'admin' : 'staff')).statusCode).toBe(404);
    }
    expect((await request('POST', '/api/erp/salaries', {}, 'admin')).statusCode).toBe(400);
  });
});
