import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { buildApp } from '../src/app.js';
import { config } from '../src/config/index.js';
import { pool, query } from '../src/db/index.js';
import { runMigrations } from '../src/db/migrate.js';
import { installTestFirebaseKeys, signedTestToken } from './helpers/auth.js';
describe.skipIf(process.env.RUN_SETTLEMENT_TESTS !== '1')('isolated registration and settlement regressions', () => {
    const app = buildApp({ logger: false });
    const send = (method: any, url: string, payload?: any) => app.inject({ method, url: `/api${url}`, payload, headers: { authorization: `Bearer ${signedTestToken()}` } });
    const admission = '2026-10-19T06:12:00Z', exit = '2026-10-31T03:31:00Z';
    const cycle = String(Date.parse(admission));
    const patient = (id = 'p1') => ({ id, fullName: 'Synthetic settlement', dateOfBirth: '1990-01-01', gender: 'Other', contactNumber: '000', emergencyContact: '000', emergencyContactName: 'Synthetic', medicalCondition: 'Synthetic', admissionDate: admission, registrationDate: admission, exitDate: exit, registrationNumber: id, advanceBilledAmount: 2600, currentDueAmount: 2600 });
    const placement = (id = 's1', patientId = 'p1', bedId = 'b1') => ({ id, patientId, roomId: 'r1', bedId, admissionDate: admission, durationDays: 12, cycleId: cycle });
    const register = (id = 'p1', bedId = 'b1') => send('POST', '/patients/register', { ...patient(id), stays: [placement(`s_${id}`, id, bedId)] });
    beforeAll(async () => {
        const target = new URL(config.getEffectiveDatabaseUrl());
        if (config.NODE_ENV !== 'test' || target.hostname !== '127.0.0.1' || target.port !== '55439' || target.pathname !== '/ngo_audit_settlement')
            throw new Error('Dedicated local settlement database required');
        expect((await query('SELECT current_database() AS db')).rows[0].db).toBe('ngo_audit_settlement');
        await runMigrations();
    });
    beforeEach(async () => {
        installTestFirebaseKeys();
        await query('TRUNCATE users,patients,rooms,stays,payments,attendance_records CASCADE');
        await query("INSERT INTO users(id,email,name,role) VALUES('test-uid-admin','admin@ngo.test','Synthetic','admin')");
        expect((await send('POST', '/rooms', { id: 'r1', roomNumber: 'R1', roomType: 'general', beds: [{ id: 'b1', bedLabel: '1' }, { id: 'b2', bedLabel: '2' }] })).statusCode).toBe(201);
    });
    afterAll(async () => { await app.close(); await pool.end(); });
    it('unmatched receipts remain visible; unsafe actions roll back and evidence-backed allocation is audited', async () => {
        await register();
        await query("INSERT INTO payments(id,patient_id,cycle_id,type,amount,payment_date) VALUES('unmatched','p1','unknown-cycle','payment',1200,CURRENT_TIMESTAMP)");
        const before = (await send('GET', '/patients/p1/financials')).json();
        expect(before.reconciliation).toMatchObject({ required: true, unallocatedNet: 1200, accountPaid: 1200 });
        expect((await send('POST', '/payments', { id: 'unsafe-collection', patientId: 'p1', cycleId: cycle, amount: 100, collectOutstanding: true })).statusCode).toBe(409);
        expect((await send('POST', '/payments', { id: 'unsafe-refund', patientId: 'p1', cycleId: cycle, type: 'refund', amount: -100 })).statusCode).toBe(409);
        expect((await send('POST', '/patients/p1/discharge', { checkoutAt: Date.parse(exit) })).statusCode).toBe(409);
        expect((await query("SELECT id FROM payments WHERE id LIKE 'unsafe-%'")).rows).toEqual([]);
        expect((await query("SELECT status FROM stays WHERE id='s_p1'")).rows[0].status).toBe('active');
        expect((await send('PATCH', '/payments/unmatched', { cycleId: cycle })).statusCode).toBe(409);
        const correction = { cycleId: cycle, reason: 'Fixture receipt evidence identifies current admission' };
        await query("INSERT INTO users(id,email,name,role) VALUES('allocation-volunteer','volunteer@ngo.test','Synthetic','volunteer')");
        const denied = await app.inject({ method: 'PATCH', url: '/api/payments/unmatched', payload: correction,
            headers: { authorization: `Bearer ${signedTestToken('allocation-volunteer')}` } });
        expect(denied.statusCode).toBe(403);
        expect((await query("SELECT cycle_id FROM payments WHERE id='unmatched'")).rows[0].cycle_id).toBe('unknown-cycle');
        expect((await send('PATCH', '/payments/unmatched', correction)).statusCode).toBe(200);
        expect((await send('PATCH', '/payments/unmatched', correction)).statusCode).toBe(200);
        const after = (await send('GET', '/patients/p1/financials')).json();
        expect(after.reconciliation).toMatchObject({ required: false, accountPaid: 1200 });
        expect(after.patient.admissionBalances[cycle].paid).toBe(1200);
        const history = (await send('GET', '/payments/unmatched/history')).json();
        expect(history.filter((r: any) => r.operation === 'UPDATE')).toHaveLength(1);
        expect(history.at(-1)).toMatchObject({ operator_uid: 'test-uid-admin', reason: correction.reason, previous_record: { cycle_id: 'unknown-cycle' }, resulting_record: { cycle_id: cycle } });
    });
    it('generic patient updates cannot inject derived financial balances even with a current version', async () => {
        await register();
        const p = (await send('GET', '/patients/p1')).json();
        expect((await send('PUT', '/patients/p1', { expectedVersion: p.version, admissionBalances: { [cycle]: { total: 0, paid: 99999 } } })).statusCode).toBe(409);
    });
    it.each(['totalPaidAmount', 'currentDueAmount', 'refundDueAmount', 'totalRefundDueAmount',
        'totalRefundedAmount', 'admissionBalances', 'stayBillingUpdates', 'advanceBilledAmount',
        'attendanceCharges', 'billingAmountOverride', 'totalPresentDays', 'totalAbsentDays']
        .flatMap(field => [null, field === 'stayBillingUpdates' ? {} : 99999].map(value => ({ field, value }))))(
        'generic patient PUT rejects derived $field=$value without changing profile or ledger', async ({ field, value }) => {
            await register();
            const before = (await query("SELECT row_to_json(p) AS data FROM patients p WHERE id='p1'")).rows[0].data;
            const response = await send('PUT', '/patients/p1', {
                expectedVersion: before.version, fullName: 'Must roll back', [field]: value,
            });
            // The shared request validator rejects malformed stay updates before
            // this route runs. A well-shaped object must still hit its guard.
            const malformedStayUpdates = field === 'stayBillingUpdates' && value === null;
            expect(response.statusCode, response.body).toBe(malformedStayUpdates ? 400 : 409);
            expect(response.json().message).toContain(malformedStayUpdates
                ? 'Invalid stay billing updates' : 'Financial balances are derived');
            expect((await query("SELECT row_to_json(p) AS data FROM patients p WHERE id='p1'")).rows[0].data).toEqual(before);
            expect((await query("SELECT id FROM payments WHERE patient_id='p1'")).rows).toEqual([]);
        });
    it('rejects inconsistent placement identities atomically and stamps every bed with the admission cycle', async () => {
        const invalid = { ...patient(), stays: [placement('first'), { ...placement('second', 'p1', 'b2'), cycleId: 'different-bed-cycle' }] };
        expect((await send('POST', '/patients/register', invalid)).statusCode).toBe(409);
        expect((await query('SELECT id FROM patients')).rows).toEqual([]);
        expect((await query('SELECT id FROM stays')).rows).toEqual([]);
        expect((await query("SELECT id FROM room_beds WHERE status<>'available'")).rows).toEqual([]);
        await register();
        expect((await send('POST', '/stays', { ...placement('second', 'p1', 'b2'), patientSnapshot: { admissionDate: 'stale' } })).statusCode).toBe(409);
        expect((await send('POST', '/stays', { ...placement('second', 'p1', 'b2'), cycleId: undefined })).statusCode).toBe(201);
        const rows = (await query('SELECT cycle_id,patient_snapshot FROM stays')).rows;
        expect(rows).toHaveLength(2);
        for (const row of rows) {
            expect(row.cycle_id).toBe(cycle);
            expect(String(row.patient_snapshot.admissionDate)).toBe(cycle);
        }
    });
    it('single-cycle untagged history stays unresolved while safe advances remain idempotent', async () => {
        await register();
        await query("INSERT INTO payments(id,patient_id,type,amount,payment_date) VALUES('legacy','p1','payment',2800,$1)", [admission]);
        const original = (await query("SELECT * FROM payments WHERE id='legacy'")).rows[0];
        const advance = { id: 'advance', patientId: 'p1', cycleId: cycle, amount: 200 };
        const responses = await Promise.all([send('POST', '/payments', advance), send('POST', '/payments', advance)]);
        expect(responses.map(r => r.statusCode).sort()).toEqual([200, 201]);
        const bill = (await send('GET', '/patients/p1/financials')).json();
        expect(bill.reconciliation).toMatchObject({ required: true, accountPaid: 3000, unallocatedNet: 2800 });
        expect(bill.patient.admissionBalances[cycle].paid).toBe(200);
        expect((await send('POST', '/payments', { id: 'collection', patientId: 'p1', cycleId: cycle, amount: 100, collectOutstanding: true })).statusCode).toBe(409);
        expect((await send('POST', '/payments', { id: 'refund', patientId: 'p1', cycleId: cycle, type: 'refund', amount: -100 })).statusCode).toBe(409);
        expect((await query("SELECT * FROM payments WHERE id='legacy'")).rows[0]).toEqual(original);
        expect((await query('SELECT id FROM payments')).rows).toHaveLength(2);
    });
    it('cycle identity conflict alone blocks financial actions without rewriting either identity', async () => {
        await register();
        await query("UPDATE stays SET patient_snapshot=jsonb_set(patient_snapshot,'{admissionDate}','\"different-snapshot\"') WHERE id='s_p1'");
        const before = (await query("SELECT cycle_id,patient_snapshot FROM stays WHERE id='s_p1'")).rows[0];
        const bill = (await send('GET', '/patients/p1/financials')).json();
        expect(bill.reconciliation).toMatchObject({ required: true, unallocatedNet: 0 });
        expect(bill.reconciliation.cycleIdentityIssues).toHaveLength(1);
        for (const payload of [
            { id: 'collection', patientId: 'p1', cycleId: cycle, amount: 100, collectOutstanding: true },
            { id: 'refund', patientId: 'p1', cycleId: cycle, type: 'refund', amount: -100 },
        ]) expect((await send('POST', '/payments', payload)).statusCode).toBe(409);
        expect((await send('POST', '/patients/p1/discharge', { checkoutAt: Date.parse(exit) })).statusCode).toBe(409);
        expect((await query("SELECT cycle_id,patient_snapshot FROM stays WHERE id='s_p1'")).rows[0]).toEqual(before);
        expect((await query("SELECT id FROM payments")).rows).toEqual([]);
    });
    it('5157-shaped historical stays retain both frozen invoices and their shared-snapshot receipt', async () => {
        await register();
        for (const suffix of ['A', 'B']) {
            await query(`INSERT INTO stays(id,patient_id,patient_name,patient_snapshot,room_id,room_number,room_type,cycle_id,
              admission_date,duration_days,expected_discharge_date,expiry_date,completed_at,status,created_by,bed_id,total_cost)
              VALUES($1,'p1','Synthetic',$2::jsonb,'r1','R1','general',$3,'2026-09-20',3,'2026-09-23','2026-09-23','2026-09-23','completed','test-uid-admin',$4,1200)`,
              [`historical${suffix}`, JSON.stringify({ admissionDate: 'shared-snapshot' }), `explicit${suffix}`, suffix === 'A' ? 'b1' : 'b2']);
        }
        await query("UPDATE patients SET admission_balances=admission_balances || $1::jsonb WHERE id='p1'", [JSON.stringify({
            explicitA: { total: 1200, finalized: true, segmentCharges: { historicalA: 1200 } },
            explicitB: { total: 1200, finalized: true, segmentCharges: { historicalB: 1200 } },
        })]);
        await query("INSERT INTO payments(id,patient_id,cycle_id,type,amount,payment_date) VALUES('snapshot-receipt','p1','shared-snapshot','payment',1200,'2026-09-20')");
        const original = (await query("SELECT row_to_json(s) AS data FROM stays s WHERE id LIKE 'historical%' ORDER BY id")).rows;
        const bill = (await send('GET', '/patients/p1/financials')).json();
        expect(bill.reconciliation).toMatchObject({ required: true, accountPaid: 1200, unallocatedNet: 1200 });
        expect(bill.reconciliation.cycleIdentityIssues).toHaveLength(2);
        for (const id of ['explicitA', 'explicitB']) expect(bill.patient.admissionBalances[id]).toMatchObject({ total: 1200, paid: 0 });
        expect((await send('POST', '/patients/p1/recalculate-billing', {})).statusCode).toBe(200);
        expect((await query("SELECT row_to_json(s) AS data FROM stays s WHERE id LIKE 'historical%' ORDER BY id")).rows).toEqual(original);
        expect((await query("SELECT cycle_id,amount FROM payments WHERE id='snapshot-receipt'")).rows[0]).toEqual({ cycle_id: 'shared-snapshot', amount: '1200.00' });
        expect((await send('POST', '/patients/p1/discharge', { checkoutAt: Date.parse(exit) })).statusCode).toBe(409);
    });
    it('stored overpayment without invoice evidence does not authorize an 800 refund', async () => {
        expect((await send('POST', '/patients', { ...patient(), advanceBilledAmount: 3200, totalPaidAmount: 4000, refundDueAmount: 0, status: 'discharged' })).statusCode).toBe(201);
        await query("INSERT INTO payments(id,patient_id,cycle_id,type,amount,payment_date) VALUES('receipt','p1',$1,'payment',4000,$2)", [cycle, admission]);
        const before = (await query("SELECT row_to_json(p) AS data FROM patients p WHERE id='p1'")).rows[0];
        const bill = (await send('GET', '/patients/p1/financials')).json();
        expect(bill.reconciliation).toMatchObject({ required: true, unallocatedNet: 0, chargeIssues: [{ reason: 'missing_invoice_evidence' }] });
        expect((await send('POST', '/payments', { id: 'unsupported-refund', patientId: 'p1', cycleId: cycle, type: 'refund', amount: -800 })).statusCode).toBe(409);
        expect((await query("SELECT row_to_json(p) AS data FROM patients p WHERE id='p1'")).rows[0]).toEqual(before);
        expect((await query('SELECT id FROM payments')).rows).toHaveLength(1);
    });
    it('successful reconciled collection, refund and discharge use the same ledger under concurrency', async () => {
        await register();
        for (let d = 19; d <= 31; d++)
            await send('POST', '/attendance', { patientId: 'p1', date: `2026-10-${d}`, payload: { status: 'Present' } });
        await query("INSERT INTO payments(id,patient_id,type,amount,payment_date) VALUES('legacy','p1','payment',1200,$1)", [admission]);
        expect((await send('PATCH', '/payments/legacy', { cycleId: cycle, reason: 'Isolated fixture original receipt identifies admission' })).statusCode).toBe(200);
        const collection = (id: string) => send('POST', '/payments', { id, patientId: 'p1', cycleId: cycle, amount: 1400, collectOutstanding: true });
        expect((await Promise.all([collection('collectionA'), collection('collectionB')])).map(r => r.statusCode).sort()).toEqual([201, 409]);
        expect((await send('POST', '/payments', { id: 'advance', patientId: 'p1', cycleId: cycle, amount: 200 })).statusCode).toBe(201);
        expect((await send('POST', '/payments', { id: 'refund', patientId: 'p1', cycleId: cycle, type: 'refund', amount: -200 })).statusCode).toBe(201);
        const discharged = await send('POST', '/patients/p1/discharge', { checkoutAt: Date.parse(exit) });
        expect(discharged.statusCode).toBe(200);
        expect(discharged.json().reconciliation).toMatchObject({ required: false, accountPaid: 2800, accountRefunded: 200 });
        expect(discharged.json().patient).toMatchObject({ totalPaidAmount: 2600, refundDueAmount: 0, currentDueAmount: 0 });
        expect((await query('SELECT sum(amount)::text AS net,count(*)::int AS count FROM payments')).rows[0]).toEqual({ net: '2600.00', count: 4 });
    });
    it('different patients competing for a bed never share a stay or partially register', async () => {
        const results = await Promise.all([register('p1'), register('p2')]);
        expect(results.map(r => r.statusCode).sort()).toEqual([201, 409]);
        expect((await query('SELECT id FROM patients')).rows).toHaveLength(1);
        const stays = (await query('SELECT id,patient_id,bed_id FROM stays')).rows;
        expect(stays).toHaveLength(1);
        const winner = results.find(r => r.statusCode === 201)!.json().patient.id;
        expect(stays[0]).toMatchObject({ id: `s_${winner}`, patient_id: winner, bed_id: 'b1' });
        expect((await register(winner)).statusCode).toBe(200);
        expect((await query('SELECT id FROM stays')).rows).toHaveLength(1);
    });
    it('a stay ID cannot be reused for a different admission cycle even with the same patient and bed', async () => {
        await register();
        const response = await send('POST', '/stays', { ...placement('s_p1'), cycleId: 'new-cycle', admissionDate: '2026-11-01' });
        expect(response.statusCode).toBe(409);
        expect((await query("SELECT cycle_id FROM stays WHERE id='s_p1'")).rows[0].cycle_id).toBe(cycle);
    });
    it('refund validation uses the persisted ledger instead of an inflated cached refundable balance', async () => {
        await register();
        await send('POST', '/payments', { id: 'paid', patientId: 'p1', cycleId: cycle, amount: 2800, method: 'cash' });
        await query("INSERT INTO payments(id,patient_id,cycle_id,type,amount,payment_date) VALUES('already-returned','p1',$1,'refund',-400,CURRENT_TIMESTAMP)", [cycle]);
        // Reproduce a stale summary: actual net is 2200, while the summary still says 2600.
        const response = await send('POST', '/payments', { id: 'must-reject', patientId: 'p1', cycleId: cycle, type: 'refund', amount: -200, method: 'cash' });
        expect(response.statusCode).toBe(409);
        expect((await query("SELECT id FROM payments WHERE id='must-reject'")).rows).toEqual([]);
    });
    it('checkout pricing is identical before and after discharge and refunds are counted once', async () => {
        await register();
        for (let d = 19; d <= 31; d++)
            await query("INSERT INTO attendance_records(id,kind,attendance_date,patient_id,payload) VALUES($1,'attendance',$2,'p1',$3)", [`a${d}`, `2026-10-${d}`, JSON.stringify({ status: d >= 29 ? 'Absent' : 'Present' })]);
        await send('POST', '/payments', { id: 'paid', patientId: 'p1', cycleId: cycle, amount: 2600, method: 'cash' });
        const before = await send('GET', '/patients/p1/financials');
        expect(before.statusCode).toBe(200);
        expect(before.json().patient).toMatchObject({ advanceBilledAmount: 2000, refundDueAmount: 600 });
        expect((await send('POST', '/payments', { id: 'returned400', patientId: 'p1', cycleId: cycle, type: 'refund', amount: -400, method: 'cash' })).statusCode).toBe(201);
        expect((await send('POST', '/patients/p1/discharge', { checkoutAt: Date.parse(exit) })).statusCode).toBe(409);
        expect((await query("SELECT status FROM stays WHERE id='s_p1'")).rows[0].status).toBe('active');
        const refund = { id: 'returned200', patientId: 'p1', cycleId: cycle, type: 'refund', amount: -200, method: 'cash' };
        expect((await send('POST', '/payments', refund)).statusCode).toBe(201);
        expect((await send('POST', '/payments', refund)).statusCode).toBe(200);
        const done = await send('POST', '/patients/p1/discharge', { checkoutAt: Date.parse(exit) });
        expect(done.statusCode).toBe(200);
        expect(done.json().patient).toMatchObject({ status: 'discharged', advanceBilledAmount: 2000, totalPaidAmount: 2000, totalRefundedAmount: 600, refundDueAmount: 0 });
        expect((await send('POST', '/patients/p1/discharge', { checkoutAt: Date.parse(exit) })).statusCode).toBe(200);
        expect((await query("SELECT current_stay_id,status FROM room_beds WHERE id='b1'")).rows[0]).toMatchObject({ current_stay_id: null, status: 'available' });
        expect((await query("SELECT occupied_beds FROM rooms WHERE id='r1'")).rows[0].occupied_beds).toBe(0);
    });
    it('multi-bed admission is atomic, retries preserve both placements and attendance is never generated', async () => {
        const body = { ...patient(), stays: [placement('s1'), placement('s2', 'p1', 'b2')] };
        const responses = await Promise.all([send('POST', '/patients/register', body), send('POST', '/patients/register', body)]);
        expect(responses.map(x => x.statusCode).sort()).toEqual([200, 201]);
        expect((await query('SELECT id FROM stays')).rows).toHaveLength(2);
        expect((await query('SELECT id FROM attendance_records')).rows).toHaveLength(0);
        expect((await query("SELECT occupied_beds FROM rooms WHERE id='r1'")).rows[0].occupied_beds).toBe(2);
        const bill = await send('GET', '/patients/p1/financials');
        expect(bill.json().patient).toMatchObject({ advanceBilledAmount: 2600, totalPaidAmount: 0, refundDueAmount: 0 });
    });
    async function markedAndPaid() {
        await register();
        for (let d = 19; d <= 31; d++)
            await send('POST', '/attendance', { patientId: 'p1', date: `2026-10-${d}`, payload: { status: 'Present' } });
        await send('POST', '/payments', { id: 'paid', patientId: 'p1', cycleId: cycle, amount: 2600, method: 'cash' });
    }
    it('concurrent distinct refunds cannot collectively spend the same excess', async () => {
        await register();
        for (let d = 19; d <= 31; d++)
            await send('POST', '/attendance', { patientId: 'p1', date: `2026-10-${d}`, payload: { status: 'Present' } });
        await send('POST', '/payments', { id: 'paid', patientId: 'p1', cycleId: cycle, amount: 2800, method: 'cash' });
        const refunds = await Promise.all(['r1', 'r2'].map(id => send('POST', '/payments', { id, patientId: 'p1', cycleId: cycle, type: 'refund', amount: -200, method: 'cash' })));
        expect(refunds.map(r => r.statusCode).sort()).toEqual([201, 409]);
        expect((await query("SELECT sum(amount)::text AS net FROM payments WHERE patient_id='p1'")).rows[0].net).toBe('2600.00');
    });
    it('discharge rechecks attendance and the ledger after waiting on a conflicting patient write', async () => {
        await markedAndPaid();
        const client = await pool.connect();
        let pending: ReturnType<typeof send> | undefined;
        try {
            await client.query('BEGIN');
            await client.query("SELECT id FROM patients WHERE id='p1' FOR UPDATE");
            const pid = (await client.query('SELECT pg_backend_pid() AS pid')).rows[0].pid;
            pending = send('POST', '/patients/p1/discharge', { checkoutAt: Date.parse(exit) }).then(r => r);
            let blocked = false;
            for (let i = 0; i < 200; i++) {
                blocked = (await query('SELECT EXISTS(SELECT 1 FROM pg_stat_activity WHERE $1=ANY(pg_blocking_pids(pid))) AS waiting', [pid])).rows[0].waiting;
                if (blocked)
                    break;
                await new Promise(r => setTimeout(r, 10));
            }
            expect(blocked).toBe(true);
            await client.query("UPDATE attendance_records SET payload='{\"status\":\"Absent\"}'::jsonb WHERE patient_id='p1' AND attendance_date='2026-10-29'");
            await client.query("UPDATE patients SET version=version+1 WHERE id='p1'");
            await client.query('COMMIT');
            expect((await pending).statusCode).toBe(409);
            expect((await query("SELECT status FROM patients WHERE id='p1'")).rows[0].status).toBe('active');
            expect((await query("SELECT status FROM stays WHERE id='s_p1'")).rows[0].status).toBe('active');
            expect((await query("SELECT current_patient_id FROM room_beds WHERE id='b1'")).rows[0].current_patient_id).toBe('p1');
        }
        finally {
            await client.query('ROLLBACK');
            client.release();
            if (pending)
                await pending;
        }
    });
    it('a bed-release failure rolls back stay closure, patient discharge and final billing', async () => {
        await markedAndPaid();
        await query("CREATE FUNCTION settlement_fail() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'synthetic bed failure'; END $$; CREATE TRIGGER settlement_fail BEFORE UPDATE ON room_beds FOR EACH ROW EXECUTE FUNCTION settlement_fail()");
        try {
            expect((await send('POST', '/patients/p1/discharge', { checkoutAt: Date.parse(exit) + 60000 })).statusCode).toBe(500);
            expect((await query("SELECT status FROM patients WHERE id='p1'")).rows[0].status).toBe('active');
            expect((await query("SELECT status FROM stays WHERE id='s_p1'")).rows[0].status).toBe('active');
            expect((await query("SELECT current_patient_id FROM room_beds WHERE id='b1'")).rows[0].current_patient_id).toBe('p1');
        }
        finally {
            await query('DROP TRIGGER settlement_fail ON room_beds; DROP FUNCTION settlement_fail()');
        }
    });
    it.each(['2026-10-31T02:30:00Z', '2026-10-31T03:30:00Z', '2026-10-31T06:30:00Z'])('checkout at %s respects the cutoff without fabricating presence', async (exitDate) => {
        await send('POST', '/patients/register', { ...patient(), exitDate, stays: [placement('s_p1')] });
        const before = (await send('GET', '/patients/p1/financials')).json().patient;
        expect(before).toMatchObject({ advanceBilledAmount: Date.parse(exitDate) <= Date.parse('2026-10-31T03:30:00Z') ? 2400 : 2600, totalPresentDays: 0, totalAbsentDays: 0, refundDueAmount: 0 });
        expect((await query('SELECT id FROM attendance_records')).rows).toHaveLength(0);
        for (let d = 19; d <= 31; d++)
            await send('POST', '/attendance', { patientId: 'p1', date: `2026-10-${d}`, payload: { status: d >= 29 ? 'Absent' : 'Present' } });
        await send('POST', '/payments', { id: 'paid', patientId: 'p1', cycleId: cycle, amount: 2600, method: 'cash' });
        const marked = (await send('GET', '/patients/p1/financials')).json().patient;
        expect(marked).toMatchObject({ advanceBilledAmount: 2000, totalPresentDays: 10, totalAbsentDays: 3, refundDueAmount: 600 });
        await send('POST', '/payments', { id: 'refund', patientId: 'p1', cycleId: cycle, amount: -600, type: 'refund', method: 'cash' });
        const done = await send('POST', '/patients/p1/discharge', { checkoutAt: Date.parse(exit) });
        expect(done.statusCode).toBe(200);
        expect(done.json().patient).toMatchObject({ advanceBilledAmount: 2000, totalPaidAmount: 2000, refundDueAmount: 0 });
    });
    it('an undecided exit starts with seven days, includes elapsed days and never creates attendance', async () => {
      // Keep authentication on the real clock; only the billing as-of changes.
      const token = signedTestToken();
      const timedSend = (method: any, url: string, payload?: any) => app.inject({ method, url: `/api${url}`, payload, headers: { authorization: `Bearer ${token}` } });
      const clock = vi.spyOn(Date, 'now').mockReturnValue(Date.parse(admission));
      try {
        expect((await timedSend('POST','/patients/register',{...patient(),exitDate:null,stays:[{...placement('s_p1'),durationDays:7}]})).statusCode).toBe(201);
        const result=(await timedSend('GET','/patients/p1/financials')).json().patient;
        expect(result).toMatchObject({advanceBilledAmount:1400,totalPresentDays:0,totalAbsentDays:0,refundDueAmount:0});
        clock.mockReturnValue(Date.parse(admission) + 9 * 86400000);
        expect((await timedSend('GET','/patients/p1/financials')).json().patient.advanceBilledAmount).toBe(2000);
        expect((await query('SELECT id FROM attendance_records')).rows).toHaveLength(0);
      } finally { clock.mockRestore(); }
    });

    it('reading a closed legacy invoice and rejecting an excess refund preserves historical charges', async () => {
      await register();
      const saved={total:2000,paid:2600,refunded:600,netPaid:2000,due:0,refundDue:0,segmentCharges:{s_p1:2000},segmentDays:{s_p1:10}};
      await query("UPDATE patients SET status='discharged',advance_billed_amount=2000,total_paid_amount=2000,refund_due_amount=0,total_refunded_amount=600,admission_balances=$1::jsonb WHERE id='p1'",[JSON.stringify({[cycle]:saved})]);
      await query("UPDATE stays SET status='completed',completed_at=$1,total_cost=2400 WHERE id='s_p1'",[exit]);
      await query("INSERT INTO payments(id,patient_id,cycle_id,type,amount,payment_date) VALUES('legacy-paid','p1',$1,'payment',2600,CURRENT_TIMESTAMP),('legacy-refund','p1',$1,'refund',-600,CURRENT_TIMESTAMP)",[cycle]);
      const before=(await query("SELECT row_to_json(p) data FROM patients p WHERE id='p1'")).rows[0].data;
      expect((await send('GET','/patients/p1/financials')).json().patient).toMatchObject({advanceBilledAmount:2000,totalPaidAmount:2000,refundDueAmount:0});
      expect((await send('GET',`/patients/p1/financials?checkoutAt=${Date.parse('2026-11-01T04:00:00Z')}`)).json().patient.advanceBilledAmount).toBe(2000);
      expect((await send('POST','/payments',{id:'over-refund',patientId:'p1',cycleId:cycle,type:'refund',amount:-200})).statusCode).toBe(409);
      expect((await query("SELECT row_to_json(p) data FROM patients p WHERE id='p1'")).rows[0].data).toEqual(before);
      expect((await query("SELECT total_cost::text FROM stays WHERE id='s_p1'")).rows[0].total_cost).toBe('2400.00');
    });

    const at = (day: number, hour = 3, minute = 30) => new Date(Date.UTC(2026, 0, day, hour, minute));
    async function syntheticAdmission(options: { days?: number; category?: string; attendants?: any[]; beds?: number } = {}) {
      const days = options.days ?? 7;
      const start = at(1, 0, 0).toISOString();
      const planned = at(days, 3, 31).toISOString();
      const id = 'p1';
      if (options.category === 'private') await query("UPDATE rooms SET room_type='private' WHERE id='r1'");
      const response = await send('POST', '/patients/register', {
        ...patient(id), admissionDate: start, registrationDate: start, exitDate: planned,
        attendants: options.attendants ?? [],
        stays: Array.from({ length: options.beds ?? 1 }, (_, index) => ({
          ...placement(`s${index + 1}`, id, `b${index + 1}`), admissionDate: start,
          durationDays: days, expectedDischargeDate: at(days + 1).toISOString(), cycleId: String(Date.parse(start)),
        })),
      });
      expect(response.statusCode, response.body).toBe(201);
      return { cycle: String(Date.parse(start)), planned, attendants: response.json().patient.attendants };
    }
    async function markPatient(days: number, status = 'Present') {
      for (let day = 1; day <= days; day++) expect((await send('POST', '/attendance', {
        patientId: 'p1', date: at(day).toISOString().slice(0, 10), payload: { status },
      })).statusCode).toBe(200);
    }
    async function pay(amount: number, cycleId: string, id = 'approved-payment') {
      const result = await send('POST', '/payments', { id, patientId: 'p1', cycleId, amount, method: 'cash' });
      expect(result.statusCode, result.body).toBe(201);
    }
    it.each([
      [7, 3, 29, 1200, 0], [7, 3, 30, 1200, 0], [7, 3, 31, 1400, 200],
      [30, 3, 31, 6000, 200], [60, 3, 31, 12000, 200],
      [61, 3, 31, 12250, 250], [61, 3, 29, 12000, 0], [61, 3, 30, 12000, 0],
    ])('General day %i checkout %i:%i UTC has total ₹%i and adjustment ₹%i exactly once', async (days, hour, minute, total, adjustment) => {
      const fixture = await syntheticAdmission({ days });
      await markPatient(days);
      const checkoutAt = at(days, hour, minute).getTime();
      const preview = await send('GET', `/patients/p1/financials?checkoutAt=${checkoutAt}`);
      expect(preview.statusCode, preview.body).toBe(200);
      expect(preview.json().patient.advanceBilledAmount).toBe(total);
      expect((await send('POST', '/patients/p1/recalculate-billing', { checkoutAt })).statusCode).toBe(200);
      await pay(total, fixture.cycle);
      // A settlement quote must not replace the ordinary booking projection.
      expect((await send('GET', `/patients/p1/financials?checkoutAt=${checkoutAt}`)).json().patient).toMatchObject({ advanceBilledAmount: total, currentDueAmount: 0, refundDueAmount: 0 });
      const discharged = await send('POST', '/patients/p1/discharge', { checkoutAt });
      expect(discharged.statusCode, discharged.body).toBe(200);
      expect(discharged.json().patient).toMatchObject({ status: 'discharged', exitDate: Date.parse(fixture.planned), dischargeDate: checkoutAt,
        advanceBilledAmount: total, totalPaidAmount: total, currentDueAmount: 0, refundDueAmount: 0 });
      const first = (await query("SELECT row_to_json(s) AS data FROM stays s WHERE patient_id='p1'")).rows;
      const final = (await send('GET', '/patients/p1/financials')).json();
      expect(final.patient.advanceBilledAmount).toBe(total);
      expect(final.patient.admissionBalances[fixture.cycle].total).toBe(total);
      const summary = first[0].data.billing_summary;
      expect(summary.checkoutAdjustment?.amount ?? 0).toBe(adjustment);
      expect((await send('POST', '/patients/p1/discharge', { checkoutAt: checkoutAt + 60000 })).statusCode).toBe(200);
      expect((await query("SELECT row_to_json(s) AS data FROM stays s WHERE patient_id='p1'")).rows).toEqual(first);
      expect((await query("SELECT id FROM payments WHERE patient_id='p1'")).rows).toHaveLength(1);
      expect((await query("SELECT status,current_stay_id FROM room_beds WHERE id='b1'")).rows[0]).toMatchObject({ status: 'available', current_stay_id: null });
    });
    it('patient and attendant attendance are independent and nested IDs with the same name remain distinct', async () => {
      const fixture = await syntheticAdmission({ days: 1, attendants: [{ name: 'Same Name' }, { name: 'Same Name' }] });
      expect(new Set(fixture.attendants.map((a: any) => a.id)).size).toBe(2);
      await markPatient(1, 'Absent');
      const payload = Object.fromEntries(fixture.attendants.map((a: any) => [a.id, { attendantId: a.id, attendantName: a.name, status: 'Present' }]));
      expect((await send('POST', '/attendance', { patientId: 'p1', date: '2026-01-01', kind: 'attendant_attendance', payload })).statusCode).toBe(200);
      expect((await send('GET', '/patients/p1/financials')).json().patient.advanceBilledAmount).toBe(400);
      payload[fixture.attendants[1].id].status = 'Absent';
      await send('POST', '/attendance', { patientId: 'p1', date: '2026-01-01', kind: 'attendant_attendance', payload });
      expect((await send('GET', '/patients/p1/financials')).json().patient.advanceBilledAmount).toBe(200);
      await markPatient(1);
      for (const a of fixture.attendants) payload[a.id].status = 'Absent';
      await send('POST', '/attendance', { patientId: 'p1', date: '2026-01-01', kind: 'attendant_attendance', payload });
      expect((await send('GET', '/patients/p1/financials')).json().patient.advanceBilledAmount).toBe(200);
    });
    it('pending patient or attendant attendance blocks finalization and preserves placement', async () => {
      const fixture = await syntheticAdmission({ days: 1, attendants: [{ name: 'Required helper' }] });
      const checkoutAt = at(1, 3, 31).getTime();
      await pay(400, fixture.cycle);
      expect((await send('POST', '/patients/p1/discharge', { checkoutAt })).statusCode).toBe(409);
      await markPatient(1);
      expect((await send('POST', '/patients/p1/discharge', { checkoutAt })).statusCode).toBe(409);
      const helper = fixture.attendants[0];
      await send('POST', '/attendance', { patientId: 'p1', date: '2026-01-01', kind: 'attendant_attendance', payload: { [helper.id]: { attendantId: helper.id, attendantName: helper.name, status: 'Pending' } } });
      expect((await send('POST', '/patients/p1/discharge', { checkoutAt })).statusCode).toBe(409);
      expect((await query("SELECT status,current_patient_id FROM room_beds WHERE id='b1'")).rows[0]).toMatchObject({ status: 'occupied', current_patient_id: 'p1' });
      await send('POST', '/attendance', { patientId: 'p1', date: '2026-01-01', kind: 'attendant_attendance', payload: { [helper.id]: { attendantId: helper.id, attendantName: helper.name, status: 'Present' } } });
      const result = await send('POST', '/patients/p1/discharge', { checkoutAt });
      expect(result.statusCode, result.body).toBe(200);
    });
    it('General multiple allocated beds charge one patient and keep occupancy separate', async () => {
      await syntheticAdmission({ days: 7, beds: 2 });
      const bill = (await send('GET', '/patients/p1/financials')).json();
      expect(bill.patient.advanceBilledAmount).toBe(1400);
      expect(bill.stays.reduce((sum: number, stay: any) => sum + stay.totalCost, 0)).toBe(1400);
      expect((await query("SELECT sum(total_cost)::text AS amount FROM stays WHERE patient_id='p1'")).rows[0].amount).toBe('1400.00');
      expect((await query("SELECT occupied_beds FROM rooms WHERE id='r1'")).rows[0].occupied_beds).toBe(2);
    });
    it('Private reserves one patient base when absent, includes one attendant and charges only present extras', async () => {
      const fixture = await syntheticAdmission({ days: 1, category: 'private', attendants: [{ name: 'A' }, { name: 'B' }, { name: 'C' }] });
      await markPatient(1, 'Absent');
      const payload = Object.fromEntries(fixture.attendants.map((a: any, i: number) => [a.id, { attendantId: a.id, attendantName: a.name, status: i < 2 ? 'Present' : 'Absent' }]));
      await send('POST', '/attendance', { patientId: 'p1', date: '2026-01-01', kind: 'attendant_attendance', payload });
      const checkoutAt = at(1, 3, 31).getTime();
      expect((await send('GET', `/patients/p1/financials?checkoutAt=${checkoutAt}`)).json().patient.advanceBilledAmount).toBe(900);
      await pay(900, fixture.cycle);
      const done = await send('POST', '/patients/p1/discharge', { checkoutAt });
      expect(done.statusCode, done.body).toBe(200);
      expect(done.json().patient.advanceBilledAmount).toBe(900);
    });
    it('General-to-Private transfer owns its date once, retains threshold and persists totals atomically', async () => {
      await syntheticAdmission({ days: 70 });
      await send('POST', '/rooms', { id: 'r_private', roomNumber: 'Private', roomType: 'private', beds: [{ id: 'pb1', bedLabel: 'P1' }] });
      const transfer = { requestId: 'transfer-approved', expectedStayIds: ['s1'], roomId: 'r_private', roomNumber: 'Private', roomType: 'private', bedId: 'pb1', shiftedAt: at(61).getTime(), exitDate: at(70, 3, 31).getTime() };
      const response = await send('POST', '/patients/p1/transfer', transfer);
      expect(response.statusCode, response.body).toBe(200);
      expect(response.json().patient.advanceBilledAmount).toBe(21000);
      const before = (await query("SELECT id,total_cost::text,billing_summary FROM stays WHERE patient_id='p1' ORDER BY id")).rows;
      expect(before.reduce((sum, stay) => sum + Number(stay.total_cost), 0)).toBe(21000);
      expect(before.reduce((sum, stay) => sum + stay.billing_summary.days, 0)).toBe(70);
      expect((await send('POST', '/patients/p1/transfer', transfer)).statusCode).toBe(200);
      expect((await query("SELECT id,total_cost::text,billing_summary FROM stays WHERE patient_id='p1' ORDER BY id")).rows).toEqual(before);
    });
    it.each([true, false])('atomic rejoin confirmed=%s preserves financial history and retries without duplicate stays', async confirmed => {
      const old = await syntheticAdmission({ days: 1 });
      await markPatient(1);
      await pay(200, old.cycle);
      expect((await send('POST', '/patients/p1/discharge', { checkoutAt: at(1, 3, 31).getTime() })).statusCode).toBe(200);
      const oldStay = (await query("SELECT row_to_json(s) AS data FROM stays s WHERE id='s1'")).rows[0].data;
      const receipts = (await query("SELECT row_to_json(p) AS data FROM payments p WHERE patient_id='p1' ORDER BY id")).rows;
      const saved = (await query("SELECT admission_balances FROM patients WHERE id='p1'")).rows[0].admission_balances[old.cycle];
      const request = { requestId: `rejoin-${confirmed}`, admissionDate: at(10).getTime(), exitDate: confirmed ? at(16).getTime() : null,
        exitDateUnconfirmed: !confirmed, roomId: 'r1', roomNumber: 'R1', roomType: 'general', bedId: 'b1', durationDays: 7 };
      const responses = await Promise.all([send('POST', '/patients/p1/rejoin', request), send('POST', '/patients/p1/rejoin', request)]);
      expect(responses.map(r => r.statusCode).sort()).toEqual([200, 201]);
      const current = (await send('GET', '/patients/p1')).json();
      expect(current).toMatchObject({ status: 'active', registrationNumber: 'p1', admissionDate: request.admissionDate, exitDate: request.exitDate });
      expect(current.admissionBalances[old.cycle]).toEqual(saved);
      expect((await query("SELECT id FROM stays WHERE patient_id='p1' AND status='active'")).rows).toHaveLength(1);
      expect((await query("SELECT row_to_json(s) AS data FROM stays s WHERE id='s1'")).rows[0].data).toEqual(oldStay);
      expect((await query("SELECT row_to_json(p) AS data FROM payments p WHERE patient_id='p1' ORDER BY id")).rows).toEqual(receipts);
      expect((await query("SELECT current_patient_id FROM room_beds WHERE id='b1'")).rows[0].current_patient_id).toBe('p1');
      expect((await send('POST', '/patients/p1/rejoin', { ...request, exitDate: at(17).getTime(), exitDateUnconfirmed: false })).statusCode).toBe(409);
    });
    it('rejoin bed conflict rolls back cycle, placement, stay and financial summaries together', async () => {
      await syntheticAdmission({ days: 1 });
      await markPatient(1);
      await pay(200, String(at(1, 0, 0).getTime()));
      expect((await send('POST', '/patients/p1/discharge', { checkoutAt: at(1, 3, 31).getTime() })).statusCode).toBe(200);
      expect((await register('p2', 'b1')).statusCode).toBe(201);
      const before = (await query("SELECT row_to_json(p) AS data FROM patients p WHERE id='p1'")).rows[0].data;
      const result = await send('POST', '/patients/p1/rejoin', { requestId: 'failed-rejoin', admissionDate: at(10).getTime(), exitDate: null,
        exitDateUnconfirmed: true, roomId: 'r1', roomNumber: 'R1', roomType: 'general', bedId: 'b1' });
      expect(result.statusCode).toBe(409);
      expect((await query("SELECT row_to_json(p) AS data FROM patients p WHERE id='p1'")).rows[0].data).toEqual(before);
      expect((await query("SELECT id FROM stays WHERE patient_id='p1'")).rows).toHaveLength(1);
      expect((await query("SELECT current_patient_id FROM room_beds WHERE id='b1'")).rows[0].current_patient_id).toBe('p2');
    });
    it('legacy last-stay completion cannot bypass pending attendance or unsettled balances', async () => {
      const fixture = await syntheticAdmission({ days: 1 });
      const complete = { status: 'completed', completedAt: at(1, 3, 31).getTime() };
      expect((await send('PUT', '/stays/s1', complete)).statusCode).toBe(409);
      await markPatient(1);
      expect((await send('PUT', '/stays/s1', complete)).statusCode).toBe(409);
      expect((await query("SELECT status,current_patient_id FROM room_beds WHERE id='b1'")).rows[0]).toMatchObject({ status: 'occupied', current_patient_id: 'p1' });
      await pay(200, fixture.cycle);
      const done = await send('PUT', '/stays/s1', complete);
      expect(done.statusCode, done.body).toBe(200);
      expect((await send('GET', '/patients/p1')).json()).toMatchObject({ status: 'discharged', dischargeDate: complete.completedAt, currentDueAmount: 0 });
    });
    it('generic patient edits and stay creation cannot bypass the explicit admission lifecycle', async () => {
      expect((await send('POST', '/patients', patient())).statusCode).toBe(201);
      expect((await send('POST', '/patients/p1/discharge', { checkoutAt: Date.parse(exit) })).statusCode).toBe(409);
      expect((await send('PUT', '/patients/p1', { status: 'discharged', dischargeDate: Date.parse(exit) })).statusCode).toBe(409);
      expect((await query("SELECT status FROM patients WHERE id='p1'")).rows[0].status).toBe('active');
      await query("UPDATE patients SET status='discharged',discharge_date=$1 WHERE id='p1'", [exit]);
      const before = (await query("SELECT row_to_json(p) AS data FROM patients p WHERE id='p1'")).rows[0].data;
      expect((await send('PUT', '/patients/p1', { status: 'active', admissionDate: at(10).getTime() })).statusCode).toBe(409);
      expect((await send('POST', '/stays', placement())).statusCode).toBe(409);
      expect((await query("SELECT row_to_json(p) AS data FROM patients p WHERE id='p1'")).rows[0].data).toEqual(before);
      expect((await query("SELECT id FROM stays WHERE patient_id='p1'")).rows).toHaveLength(0);
    });
    it.each([['general', 1400, 400, 1000], ['private', 4900, 1400, 3500]])('early %s checkout preview authorizes the exact refund and survives its ledger write', async (category, advance, refundAmount, finalAmount) => {
      const fixture = await syntheticAdmission({ days: 7, category: String(category) });
      await markPatient(5);
      await pay(Number(advance), fixture.cycle);
      const refund = { id: 'early-return', patientId: 'p1', cycleId: fixture.cycle, amount: -Number(refundAmount), type: 'refund', method: 'cash' };
      expect((await send('POST', '/payments', refund)).statusCode).toBe(409);
      const checkoutAt = at(5, 3, 31).getTime();
      const recalculated = await send('POST', '/patients/p1/recalculate-billing', { checkoutAt });
      expect(recalculated.statusCode, recalculated.body).toBe(200);
      expect(recalculated.json().patient).toMatchObject({ advanceBilledAmount: Number(finalAmount), refundDueAmount: Number(refundAmount) });
      const returned = await send('POST', '/payments', refund);
      expect(returned.statusCode, returned.body).toBe(201);
      expect((await send('GET', `/patients/p1/financials?checkoutAt=${checkoutAt}`)).json().patient).toMatchObject({ advanceBilledAmount: Number(finalAmount), refundDueAmount: 0, currentDueAmount: 0 });
      const done = await send('POST', '/patients/p1/discharge', { checkoutAt });
      expect(done.statusCode, done.body).toBe(200);
      expect(done.json().patient).toMatchObject({ exitDate: Date.parse(fixture.planned), dischargeDate: checkoutAt,
        advanceBilledAmount: Number(finalAmount), refundDueAmount: 0, currentDueAmount: 0 });
    });
    it('collects the overdue checkout projection once and retains an unrelated identity warning', async () => {
      const start = '2026-10-16T07:30:00Z', planned = '2026-10-23T14:30:00Z';
      const current = String(Date.parse(start)), checkoutAt = Date.parse('2026-10-28T11:44:00Z');
      const registration = await send('POST', '/patients/register', { ...patient(), admissionDate: start, registrationDate: start, exitDate: planned,
        attendants: [{ id: 'helper', name: 'Helper', startDate: '2026-10-16' }],
        stays: [{ ...placement('extension-stay'), admissionDate: start, durationDays: 8, expectedDischargeDate: planned, cycleId: current }] });
      expect(registration.statusCode, registration.body).toBe(201);
      const attendant = registration.json().patient.attendants[0];
      for (let day = 16; day <= 28; day++) {
        const date = `2026-10-${day}`;
        await send('POST', '/attendance', { patientId: 'p1', date, payload: { status: 'Present' } });
        await send('POST', '/attendance', { patientId: 'p1', date, kind: 'attendant_attendance', payload: {
          [attendant.id]: { attendantId: attendant.id, status: 'Present' },
        } });
      }
      await pay(3200, current, 'original');
      await query(`INSERT INTO stays(id,patient_id,patient_name,patient_snapshot,room_id,room_number,room_type,cycle_id,
        admission_date,duration_days,expected_discharge_date,expiry_date,completed_at,status,created_by,bed_id,total_cost)
        VALUES('historic','p1','Synthetic',$1::jsonb,'r1','R1','general','historic-cycle','2025-01-01',1,'2025-01-02','2025-01-02','2025-01-02','completed','test-uid-admin','b1',200)`,
        [JSON.stringify({ admissionDate: 'conflicting-historic-cycle' })]);
      const preview = () => send('GET', `/patients/p1/financials?checkoutAt=${checkoutAt}`);
      const before = (await preview()).json();
      expect(before.patient.admissionBalances[current]).toMatchObject({ total: 5200, netPaid: 3200, due: 2000, reconciliationRequired: false });
      expect(before.reconciliation.required).toBe(true);
      const payload = { id: 'extension-payment', patientId: 'p1', cycleId: current, amount: 2000, method: 'cash', collectOutstanding: true, checkoutAt };
      const clock = vi.spyOn(Date, 'now').mockReturnValue(checkoutAt + 60000);
      try {
        expect((await send('POST', '/payments', payload)).statusCode).toBe(201);
        expect((await send('POST', '/payments', payload)).statusCode).toBe(200);
      } finally { clock.mockRestore(); }
      const after = (await preview()).json();
      expect(after.patient.admissionBalances[current]).toMatchObject({ total: 5200, netPaid: 5200, due: 0 });
      expect(after.reconciliation.required).toBe(true);
      expect(after.reconciliation.cycleIdentityIssues).toHaveLength(1);
      expect((await query("SELECT id FROM payments WHERE id='extension-payment'")).rows).toHaveLength(1);
    });

    async function octoberBooking(category = 'general', absentDays: number[] = []) {
      const start = '2026-10-22T11:57:00Z', planned = '2026-10-31T03:30:00Z';
      const bookingCycle = String(Date.parse(start));
      if (category === 'private') await query("UPDATE rooms SET room_type='private' WHERE id='r1'");
      const registered = await send('POST', '/patients/register', {
        ...patient(), admissionDate: start, registrationDate: start, exitDate: planned,
        attendants: [{ id: 'october-attendant', name: 'Synthetic', startDate: '2026-10-22' }],
        stays: [{ ...placement('october-stay'), admissionDate: start, durationDays: 9,
          expectedDischargeDate: planned, cycleId: bookingCycle }],
      });
      expect(registered.statusCode, registered.body).toBe(201);
      const attendant = registered.json().patient.attendants[0];
      for (let day = 22; day <= 31; day++) {
        const date = `2026-10-${day}`;
        expect((await send('POST', '/attendance', { patientId: 'p1', date, payload: { status: 'Present' } })).statusCode).toBe(200);
        expect((await send('POST', '/attendance', { patientId: 'p1', date, kind: 'attendant_attendance', payload: {
          [attendant.id]: { attendantId: attendant.id, status: absentDays.includes(day) ? 'Absent' : 'Present' },
        } })).statusCode).toBe(200);
      }
      return { cycle: bookingCycle, planned: Date.parse(planned), checkoutAt: Date.parse('2026-10-22T11:59:55.196Z') };
    }
    const persistedFinancialState = async () => (await query(`SELECT
      (SELECT jsonb_agg(to_jsonb(p)) FROM patients p WHERE id='p1') AS patient,
      (SELECT jsonb_agg(to_jsonb(s) ORDER BY id) FROM stays s WHERE patient_id='p1') AS stays,
      (SELECT jsonb_agg(to_jsonb(p) ORDER BY id) FROM payments p WHERE patient_id='p1') AS payments,
      (SELECT jsonb_agg(to_jsonb(a) ORDER BY id) FROM attendance_records a WHERE patient_id='p1') AS attendance`)).rows[0];

    it('October preview/cancel is read-only; stale active checkout cannot truncate booking or authorize an excess collection', async () => {
      const f = await octoberBooking();
      await pay(2000, f.cycle, 'october-first');
      await pay(2000, f.cycle, 'october-second');
      // Reproduce the already persisted production preview in the isolated DB.
      expect((await send('POST', '/patients/p1/recalculate-billing', { checkoutAt: f.checkoutAt })).json().patient)
        .toMatchObject({ advanceBilledAmount: 400, totalPaidAmount: 4000, refundDueAmount: 3600 });
      const before = await persistedFinancialState();
      for (let retry = 0; retry < 2; retry++) {
        expect((await send('GET', `/patients/p1/financials?checkoutAt=${f.checkoutAt}`)).json().patient)
          .toMatchObject({ advanceBilledAmount: 400, totalPaidAmount: 4000, refundDueAmount: 3600 });
        expect((await send('GET', '/patients/p1/financials')).json().patient)
          .toMatchObject({ advanceBilledAmount: 4000, totalPaidAmount: 4000, currentDueAmount: 0, refundDueAmount: 0 });
      }
      expect(await persistedFinancialState()).toEqual(before);
      expect((await send('GET', `/patients/p1/financials?checkoutAt=${f.planned}`)).json().patient.advanceBilledAmount).toBe(3600);
      expect((await send('GET', `/patients/p1/financials?checkoutAt=${f.planned + 60000}`)).json().patient.advanceBilledAmount).toBe(4000);
      const rejected = await send('POST', '/patients/p1/discharge', { checkoutAt: f.checkoutAt });
      expect(rejected.statusCode).toBe(409);
      expect(rejected.body).toContain('refund 3600.00');
      expect(await persistedFinancialState()).toEqual(before);
      expect((await send('POST', '/payments', { id: 'excess', patientId: 'p1', cycleId: f.cycle, amount: 1, collectOutstanding: true })).statusCode).toBe(409);
      // A deliberate ordinary recalculation repairs only this current projection.
      expect((await send('POST', '/patients/p1/recalculate-billing', {})).json().patient.advanceBilledAmount).toBe(4000);
      const stored = (await query("SELECT admission_balances FROM patients WHERE id='p1'")).rows[0].admission_balances[f.cycle];
      expect(stored.checkoutAt).toBeNull();
    });

    it.each([['general', 400], ['private', 700]])('confirmed early %s checkout ignores future Present marks and freezes actual settlement', async (category, total) => {
      const f = await octoberBooking(String(category));
      await pay(Number(total), f.cycle);
      const done = await send('POST', '/patients/p1/discharge', { checkoutAt: f.checkoutAt });
      expect(done.statusCode, done.body).toBe(200);
      expect(done.json().patient).toMatchObject({ status: 'discharged', dischargeDate: f.checkoutAt,
        advanceBilledAmount: total, totalPaidAmount: total, currentDueAmount: 0, refundDueAmount: 0 });
      expect((await send('GET', '/patients/p1/financials')).json().patient.advanceBilledAmount).toBe(total);
      expect((await query("SELECT count(*)::int AS count FROM attendance_records WHERE patient_id='p1'")).rows[0].count).toBe(20);
    });

    it('early refund uses an explicit checkout quote without persisting readiness, retries safely and permits discharge', async () => {
      const f = await octoberBooking();
      await pay(2000, f.cycle, 'first');
      await pay(2000, f.cycle, 'second');
      const before = await persistedFinancialState();
      expect((await send('GET', `/patients/p1/financials?checkoutAt=${f.checkoutAt}`)).json().patient.refundDueAmount).toBe(3600);
      expect(await persistedFinancialState()).toEqual(before);
      const refund = { id: 'explicit-checkout-refund', patientId: 'p1', cycleId: f.cycle, amount: -3600,
        type: 'refund', method: 'cash', checkoutAt: f.checkoutAt };
      expect((await send('POST', '/payments', { ...refund, amount: -3601 })).statusCode).toBe(409);
      expect(await persistedFinancialState()).toEqual(before);
      const returned = await send('POST', '/payments', refund);
      expect(returned.statusCode, returned.body).toBe(201);
      expect((await send('POST', '/payments', refund)).statusCode).toBe(200);
      // The checkout context is part of the payment retry identity.
      expect((await send('POST', '/payments', { ...refund, checkoutAt: f.planned })).statusCode).toBe(409);
      expect((await query("SELECT count(*)::int AS n,sum(amount)::text AS net FROM payments WHERE patient_id='p1'")).rows[0])
        .toEqual({ n: 3, net: '400.00' });
      expect((await send('GET', `/patients/p1/financials?checkoutAt=${f.checkoutAt}`)).json().patient)
        .toMatchObject({ advanceBilledAmount: 400, totalPaidAmount: 400, currentDueAmount: 0, refundDueAmount: 0 });
      const done = await send('POST', '/patients/p1/discharge', { checkoutAt: f.checkoutAt });
      expect(done.statusCode, done.body).toBe(200);
      expect(done.json().patient).toMatchObject({ status: 'discharged', advanceBilledAmount: 400,
        totalPaidAmount: 400, totalRefundedAmount: 3600, refundDueAmount: 0 });
      expect((await send('POST', '/payments', refund)).statusCode).toBe(200);
    });

    it('concurrent early refunds cannot spend the same excess and invalid checkout contexts leave no ledger row', async () => {
      const f = await octoberBooking();
      await pay(4000, f.cycle);
      const refund = { patientId: 'p1', cycleId: f.cycle, amount: -3600,
        type: 'refund', method: 'cash', checkoutAt: f.checkoutAt };
      const before = await persistedFinancialState();
      for (const invalid of [
        { ...refund, cycleId: 'wrong-cycle' },
        { ...refund, checkoutAt: Date.parse('2026-10-21T11:00:00Z') },
        { ...refund, checkoutAt: 'invalid' },
        { ...refund, type: 'payment', amount: 1 },
      ]) {
        expect((await send('POST', '/payments', { id: 'invalid', ...invalid })).statusCode).toBeGreaterThanOrEqual(400);
        expect(await persistedFinancialState()).toEqual(before);
      }
      const results = await Promise.all(['concurrent-one', 'concurrent-two'].map(id => send('POST', '/payments', { id, ...refund })));
      expect(results.map(r => r.statusCode).sort()).toEqual([201, 409]);
      expect((await query("SELECT count(*)::int AS n,sum(amount)::text AS net FROM payments WHERE patient_id='p1'")).rows[0])
        .toEqual({ n: 2, net: '400.00' });
    });

    it('partial payment and attendee absences retain booking rates and the existing 09:00 settlement boundary', async () => {
      const f = await octoberBooking('general', [25, 31]);
      await pay(1400, f.cycle);
      const before = await persistedFinancialState();
      expect((await send('GET', '/patients/p1/financials')).json().patient)
        .toMatchObject({ advanceBilledAmount: 3600, totalPaidAmount: 1400, currentDueAmount: 2200 });
      // Booking includes Oct 31; actual checkout at 09:00 excludes that date.
      expect((await send('GET', `/patients/p1/financials?checkoutAt=${f.planned}`)).json().patient)
        .toMatchObject({ advanceBilledAmount: 3400, currentDueAmount: 2000 });
      expect((await send('GET', `/patients/p1/financials?checkoutAt=${f.planned + 60000}`)).json().patient.advanceBilledAmount).toBe(3600);
      expect(await persistedFinancialState()).toEqual(before);
      await send('POST', '/patients/p1/recalculate-billing', { checkoutAt: f.checkoutAt });
      const remaining = { id: 'remaining', patientId: 'p1', cycleId: f.cycle, amount: 2200, collectOutstanding: true };
      expect((await send('POST', '/payments', remaining)).statusCode).toBe(201);
      expect((await send('POST', '/payments', remaining)).statusCode).toBe(200);
      expect((await send('GET', '/patients/p1/financials')).json().patient)
        .toMatchObject({ advanceBilledAmount: 3600, totalPaidAmount: 3600, currentDueAmount: 0, refundDueAmount: 0 });
      expect((await query("SELECT count(*)::int AS count FROM payments WHERE patient_id='p1'")).rows[0].count).toBe(2);
    });
});
