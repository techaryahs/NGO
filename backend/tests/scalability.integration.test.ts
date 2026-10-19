import { beforeAll, afterAll, describe, expect, it, vi } from 'vitest';
import { performance } from 'node:perf_hooks';
import { mkdir, writeFile } from 'node:fs/promises';
import { buildApp } from '../src/app.js';
import { config } from '../src/config/index.js';
import { pool, query } from '../src/db/index.js';
import { runMigrations } from '../src/db/migrate.js';
import { installTestFirebaseKeys, signedTestToken } from './helpers/auth.js';

// Opt in separately from the normal PostgreSQL integration suite. Every write
// below is guarded against the exact disposable target before migrations run.
const enabled = process.env.RUN_SCALE_INTEGRATION === '1';
describe.skipIf(!enabled)('bounded synthetic PostgreSQL scalability evidence', () => {
  const app = buildApp({ logger: false });
  const artifactDir = new URL('../../audit/code-workflow-20261018/', import.meta.url);
  const stages: any[] = [];
  let authHeaders: { authorization: string };
  let safeTargetVerified = false;
  const phase = (process.env.SCALE_PHASE || 'baseline').replace(/[^a-z0-9_-]/gi, '');
  const rounded = (value: number) => Math.round(value * 100) / 100;
  const quantile = (values: number[], p: number) => [...values].sort((a, b) => a - b)[Math.max(0, Math.ceil(values.length * p) - 1)];

  beforeAll(async () => {
    const target = new URL(config.getEffectiveDatabaseUrl());
    if (process.env.NODE_ENV !== 'test' || target.hostname !== '127.0.0.1' || target.port !== '55439'
      || target.pathname !== '/ngo_audit_scale' || decodeURIComponent(target.username) !== 'ngo_audit'
      || config.POSTGRES_DB !== 'ngo_audit_scale' || config.POSTGRES_HOST !== '127.0.0.1'
      || config.POSTGRES_PORT !== 55439 || config.POSTGRES_USER !== 'ngo_audit') {
      throw new Error('Refusing scale benchmark outside exact disposable 127.0.0.1:55439/ngo_audit_scale as ngo_audit');
    }
    const identity = (await query("SELECT current_database() AS db, current_user AS username, inet_server_port() AS port, current_setting('server_version_num')::int AS version")).rows[0];
    expect(identity).toMatchObject({ db: 'ngo_audit_scale', username: 'ngo_audit', port: 55439 });
    expect(identity.version).toBeGreaterThanOrEqual(160000);
    expect(identity.version).toBeLessThan(170000);
    safeTargetVerified = true;
    await runMigrations();
    installTestFirebaseKeys();
    authHeaders = { authorization: `Bearer ${signedTestToken()}` };
    await app.ready();
    await mkdir(artifactDir, { recursive: true });
  }, 60_000);

  afterAll(async () => {
    if (safeTargetVerified && stages.length) {
      await writeFile(new URL(`scale-${phase}.json`, artifactDir), JSON.stringify({
        capturedAt: new Date().toISOString(), phase,
        environment: { node: process.version, postgresMajor: 16, target: '127.0.0.1:55439/ngo_audit_scale', transport: 'Fastify.inject in process (no HTTP/TLS network)', poolMax: config.DB_POOL_MAX },
        limits: ['Synthetic local warm-cache benchmark; timings are descriptive, not production SLOs.', 'No photos, real personal data, external Firebase, VPS or existing application database involved.', 'Seed bypasses API workflows; correctness assertions exercise production read routes.', 'Concurrent users on WAN, Flutter rendering and sustained multi-hour load were not measured.'],
        stages,
      }, null, 2));
    }
    vi.restoreAllMocks();
    await app.close();
    await pool.end();
  });

  async function seed(count: number) {
    if (!safeTargetVerified) throw new Error('Disposable target was not verified');
    const start = performance.now();
    await query('TRUNCATE users, rooms, room_beds, patients, stays, patient_attendants, payments, attendance_records, patient_photos, sponsorships CASCADE');
    await query("INSERT INTO users(id,email,name,role) VALUES('test-uid-admin','scale@ngo.test','Synthetic Scale Admin','admin')");
    await query("INSERT INTO rooms(id,room_number,room_type) VALUES('scale-room','SYNTHETIC','general')");
    await query(`INSERT INTO patients(id, full_name, search_key, date_of_birth, gender, contact_number,
        emergency_contact, emergency_contact_name, medical_condition, admission_date, registration_number,
        total_paid_amount, current_due_amount, created_by, status)
      SELECT 'scale-p-'||i, 'Synthetic Patient '||lpad(i::text,5,'0'), 'synthetic patient '||lpad(i::text,5,'0'),
        '1990-01-01'::date, 'Other', '000', '000', 'Synthetic Contact', 'Synthetic only',
        '2026-01-01'::timestamptz + i * interval '1 second', 'SCALE-'||i, 0.50, 9.50, 'test-uid-admin', 'discharged'
      FROM generate_series(1,$1::int) i`, [count]);
    await query(`INSERT INTO patient_attendants(id,patient_id,name,age)
      SELECT 'scale-a-'||i,'scale-p-'||i,'Synthetic Attendant '||i,'32' FROM generate_series(1,$1::int) i`, [count]);
    await query(`INSERT INTO payments(id,patient_id,amount,payment_date,transaction_id)
      SELECT 'scale-pay-'||i||'-'||j, 'scale-p-'||i, 0.10,
        '2026-01-01'::timestamptz + (i*5+j)*interval '1 second', 'scale-tx-'||i||'-'||j
      FROM generate_series(1,$1::int) i CROSS JOIN generate_series(1,5) j`, [count]);
    await query(`INSERT INTO stays(id,patient_id,patient_name,room_id,room_number,room_type,admission_date,
        duration_days,expected_discharge_date,expiry_date,completed_at,status,created_by)
      SELECT 'scale-stay-'||i||'-'||j,'scale-p-'||i,'Synthetic Patient '||i,'scale-room','SYNTHETIC','general',
        '2026-01-01'::timestamptz + (i*2+j)*interval '1 second',2,'2026-02-01'::timestamptz,
        '2026-02-01'::timestamptz,'2026-02-01'::timestamptz,'completed','test-uid-admin'
      FROM generate_series(1,$1::int) i CROSS JOIN generate_series(1,2) j`, [count]);
    await query(`INSERT INTO attendance_records(id,kind,attendance_date,patient_id,payload)
      SELECT 'attendance/'||('2026-01-01'::date+d)::text||'/scale-p-'||i, 'attendance',
        '2026-01-01'::date+d, 'scale-p-'||i,
        jsonb_build_object('isPresent',true,'patientId','scale-p-'||i,'note','Synthetic attendance')
      FROM generate_series(1,$1::int) i CROSS JOIN generate_series(0,29) d`, [count]);
    for (const table of ['patients', 'patient_attendants', 'payments', 'stays', 'attendance_records']) await query(`ANALYZE ${table}`);
    const counts = (await query(`SELECT (SELECT count(*)::int FROM patients) AS patients,
      (SELECT count(*)::int FROM patient_attendants) AS attendants,
      (SELECT count(*)::int FROM payments) AS payments,(SELECT count(*)::int FROM stays) AS stays,
      (SELECT count(*)::int FROM attendance_records) AS attendance`)).rows[0];
    expect(counts).toEqual({ patients: count, attendants: count, payments: count * 5, stays: count * 2, attendance: count * 30 });
    return { counts, seedMs: rounded(performance.now() - start) };
  }

  async function request(url: string) {
    const start = performance.now();
    const response = await app.inject({ method: 'GET', url: `/api${url}`, headers: authHeaders });
    const durationMs = performance.now() - start;
    expect(response.statusCode, `${url}: ${response.body.slice(0,300)}`).toBe(200);
    return { durationMs, bytes: Buffer.byteLength(response.body), body: response.json(), headers: response.headers };
  }

  async function measure(name: string, url: string, repetitions: number, check: (body: any) => void) {
    await request(url); // Warm routes, auth keys, connection and DB caches.
    const timings: number[] = [];
    let bytes = 0;
    const spy = vi.spyOn(pool, 'query');
    try {
      for (let i=0; i<repetitions; i++) {
        const result = await request(url);
        timings.push(result.durationMs); bytes = result.bytes; check(result.body);
      }
      return { name, url, repetitions, minMs: rounded(Math.min(...timings)), medianMs: rounded(quantile(timings,0.5)), maxMs: rounded(Math.max(...timings)), bytes, queriesPerRequest: spy.mock.calls.length / repetitions };
    } finally { spy.mockRestore(); }
  }

  for (const count of [1_000,10_000]) {
    it(`${count} patients: complete paginated reads, financial totals, filtered history and bounded concurrent reads`, async () => {
      const seeded = await seed(count);
      const measurements: any[] = [];
      const checkPatients = (expected: number) => (body: any[]) => {
        expect(body).toHaveLength(expected);
        for (const patient of body) {
          expect(patient.attendants).toHaveLength(1);
          expect(patient.payments).toHaveLength(5);
          expect(patient.payments.every((payment: any) => payment.patientId === patient.id)).toBe(true);
          expect(patient.payments.reduce((sum: number,payment: any) => sum + Math.round(payment.amount*100),0)).toBe(50);
          expect(patient.totalPaidAmount).toBe(0.5);
        }
      };
      measurements.push(await measure('patients-default', '/patients?format=map', 3, body => expect(Object.keys(body)).toHaveLength(500)));
      measurements.push(await measure('payments-default', '/payments?format=map', 3, body => expect(Object.keys(body)).toHaveLength(500)));
      measurements.push(await measure('patients-page-50', '/patients?limit=50', 3, checkPatients(50)));
      measurements.push(await measure('patients-page-500', '/patients?limit=500', 3, checkPatients(500)));
      measurements.push(await measure('patients-page-max', '/patients?limit=5000', 3, checkPatients(Math.min(count,5000))));
      measurements.push(await measure('patient-exact-search', `/patients?search=Patient%20${String(count).padStart(5,'0')}`, 3, body => { checkPatients(1)(body); expect(body[0].id).toBe(`scale-p-${count}`); }));
      measurements.push(await measure('stays-complete', '/stays?format=map', 2, body => expect(Object.keys(body)).toHaveLength(count*2)));
      measurements.push(await measure('attendance-day', '/attendance?date=2026-01-15&kind=attendance&format=map', 2, body => expect(Object.keys(body)).toHaveLength(count)));
      measurements.push(await measure('attendance-month', '/attendance?startDate=2026-01-01&endDate=2026-01-30&kind=attendance&format=map', 2, body => { expect(Object.keys(body)).toHaveLength(30); expect(Object.values(body).reduce((sum:number,day:any) => sum+Object.keys(day).length,0)).toBe(count*30); }));
      const pageStart = performance.now();
      const ids = new Set<string>();
      let patientBytes=0; let patientRequests=0;
      // Model a complete client collection load using the supported pagination.
      for (let offset=0; offset<=count; offset+=500) {
        const result=await request(`/patients?limit=500&offset=${offset}&format=map`);
        patientRequests++; patientBytes+=result.bytes;
        for (const id of Object.keys(result.body)) { expect(ids.has(id)).toBe(false); ids.add(id); }
      }
      expect(ids.size).toBe(count);
      const patientLoad={ requests:patientRequests, uniquePatients:ids.size, bytes:patientBytes, durationMs:rounded(performance.now()-pageStart) };
      let cursorPatientLoad: any;
      const initialCursorPage = await request('/patients?limit=500&format=map');
      if (initialCursorPage.headers['x-pagination-mode'] === 'cursor') {
        const cursorStart=performance.now();
        const cursorIds=new Set<string>();
        let result=initialCursorPage; let cursorRequests=0; let cursorBytes=0;
        while(true) {
          cursorRequests++; cursorBytes+=result.bytes;
          for(const id of Object.keys(result.body)) { expect(cursorIds.has(id)).toBe(false); cursorIds.add(id); }
          const cursor=result.headers['x-next-cursor'];
          if(!cursor) break;
          expect(cursorRequests).toBeLessThanOrEqual(Math.ceil(count/500));
          result=await request(`/patients?limit=500&format=map&cursor=${encodeURIComponent(String(cursor))}`);
        }
        expect(cursorIds.size).toBe(count);
        cursorPatientLoad={requests:cursorRequests,uniquePatients:cursorIds.size,bytes:cursorBytes,durationMs:rounded(performance.now()-cursorStart+initialCursorPage.durationMs)};
      }
      const paymentStart=performance.now();
      const paymentIds=new Set<string>(); let paymentCents=0; let paymentRequests=0; let paymentBytes=0;
      for(let offset=0;offset<=count*5;offset+=5000) {
        const result=await request(`/payments?limit=5000&offset=${offset}`);
        paymentRequests++; paymentBytes+=result.bytes;
        for(const payment of result.body) { expect(paymentIds.has(payment.id)).toBe(false); paymentIds.add(payment.id); paymentCents+=Math.round(payment.amount*100); }
      }
      expect(paymentIds.size).toBe(count*5); expect(paymentCents).toBe(count*50);
      const paymentLoad={requests:paymentRequests,uniquePayments:paymentIds.size,totalCents:paymentCents,bytes:paymentBytes,durationMs:rounded(performance.now()-paymentStart)};
      const concurrent: any[]=[];
      for(const pageSize of [50,500]) {
        const started=performance.now();
        const results=await Promise.all(Array.from({length:20},()=>request(`/patients?limit=${pageSize}`)));
        for(const result of results) expect(result.body).toHaveLength(pageSize);
        const durationMs=performance.now()-started;
        concurrent.push({pageSize,concurrency:20,requests:20,status200:20,totalMs:rounded(durationMs),requestsPerSecond:rounded(20/(durationMs/1000)),medianMs:rounded(quantile(results.map(x=>x.durationMs),0.5)),p95Ms:rounded(quantile(results.map(x=>x.durationMs),0.95)),bytes:results.reduce((sum,x)=>sum+x.bytes,0)});
      }
      const plans: any[]=[];
      for(const [name,sql,params] of [
        ['patient-search', 'SELECT p.* FROM patients p WHERE (p.full_name ILIKE $1 OR p.search_key ILIKE $1 OR p.registration_number ILIKE $1) ORDER BY p.admission_date DESC LIMIT 500 OFFSET 0', [`%Patient ${String(count).padStart(5,'0')}%`]],
        ['attendance-month', "SELECT id,kind,attendance_date::text,patient_id,payload,created_at,updated_at FROM attendance_records WHERE attendance_date >= $1 AND attendance_date <= $2 AND kind=$3 ORDER BY attendance_date DESC", ['2026-01-01','2026-01-30','attendance']],
      ] as [string,string,unknown[]][]) plans.push({name,explain:(await query(`EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) ${sql}`,params)).rows[0]['QUERY PLAN']});
      const stage={...seeded,measurements,patientLoad,cursorPatientLoad,paymentLoad,concurrent,plans,rssBytesAtEnd:process.memoryUsage().rss};
      stages.push(stage);
      console.log('SCALE_STAGE',JSON.stringify({...stage,plans:plans.map(plan=>({name:plan.name,executionMs:plan.explain[0]['Execution Time'],rootNode:plan.explain[0].Plan['Node Type']}))}));
    }, 180_000);
  }

  it('cursor pages preserve tied timestamps and microseconds, survive deleted boundary rows, and reject malformed or cross-collection cursors', async () => {
    await seed(1_001);
    await query("UPDATE patients SET admission_date='2026-01-01T00:00:00.000123Z'; UPDATE payments SET payment_date='2026-01-01T00:00:00.000456Z'");
    for(const collection of ['patients','payments']) {
      const expectedCount=Number((await query(`SELECT count(*)::int AS n FROM ${collection}`)).rows[0].n);
      let page=await request(`/${collection}?limit=500`);
      expect(page.headers['x-pagination-mode']).toBe('cursor');
      expect(page.body).toHaveLength(500);
      const cursor=String(page.headers['x-next-cursor']);
      expect(cursor).not.toBe('undefined');
      const decoded=JSON.parse(Buffer.from(cursor,'base64url').toString('utf8'));
      expect(decoded.date).toBe(`2026-01-01T00:00:00.000${collection==='patients'?'123':'456'}Z`);
      const boundary=page.body[499].id;
      if(collection==='patients') {
        for(const table of ['attendance_records','stays','payments','patient_attendants']) await query(`DELETE FROM ${table} WHERE patient_id=$1`,[boundary]);
      }
      await query(`DELETE FROM ${collection} WHERE id=$1`,[boundary]);
      const ids=new Set<string>(page.body.map((row:any)=>row.id));
      let pages=1;
      while(page.headers['x-next-cursor']) {
        page=await request(`/${collection}?limit=500&cursor=${encodeURIComponent(String(page.headers['x-next-cursor']))}`);
        pages++;
        expect(pages).toBeLessThanOrEqual(Math.ceil(expectedCount/500));
        for(const row of page.body) { expect(ids.has(row.id)).toBe(false); ids.add(row.id); }
      }
      expect(ids.size).toBe(expectedCount);
      expect(page.headers['x-pagination-mode']).toBe('cursor');
      for(const badCursor of ['!', '', Buffer.from('{}').toString('base64url'), Buffer.from(JSON.stringify({...decoded,date:'2026-02-30T00:00:00.000123Z'})).toString('base64url'), Buffer.from(JSON.stringify({...decoded,version:2})).toString('base64url')]) {
        const invalid=await app.inject({method:'GET',url:`/api/${collection}?cursor=${encodeURIComponent(badCursor)}`,headers:authHeaders});
        expect(invalid.statusCode).toBe(400);
      }
      for(const url of [`/${collection}?cursor=${cursor}&offset=1`, `/${collection==='patients'?'payments':'patients'}?cursor=${cursor}`]) {
        const invalid=await app.inject({method:'GET',url:`/api${url}`,headers:authHeaders});
        expect(invalid.statusCode).toBe(400);
      }
      const empty=await request(`/${collection}?limit=500&offset=999999`);
      expect(empty.body).toEqual([]); expect(empty.headers['x-pagination-mode']).toBe('cursor'); expect(empty.headers['x-next-cursor']).toBeUndefined();
    }
    // Two timestamps in the same JavaScript millisecond must remain distinct.
    await query("UPDATE patients SET admission_date='2025-01-01'; UPDATE patients SET admission_date='2026-01-01T00:00:00.000124Z' WHERE id='scale-p-2'; UPDATE patients SET admission_date='2026-01-01T00:00:00.000123Z' WHERE id='scale-p-1'");
    const precise=await request('/patients?limit=1');
    expect(precise.body[0].id).toBe('scale-p-2');
    const next=await request(`/patients?limit=1&cursor=${encodeURIComponent(String(precise.headers['x-next-cursor']))}`);
    expect(next.body[0].id).toBe('scale-p-1');
  },60_000);

  it('attendance native date ordering and patient filtering remain correct at 300000 records', async () => {
    const seeded=await seed(10_000);
    const select='SELECT id,kind,attendance_date::text AS attendance_date,patient_id,payload,created_at,updated_at FROM attendance_records';
    const filter='WHERE attendance_date >= $1 AND attendance_date <= $2 AND kind=$3';
    const parameters=['2026-01-01','2026-01-30','attendance'];
    const before=(await query(`EXPLAIN (ANALYZE,BUFFERS,FORMAT JSON) ${select} ${filter} ORDER BY attendance_date DESC`,parameters)).rows[0]['QUERY PLAN'];
    const after=(await query(`EXPLAIN (ANALYZE,BUFFERS,FORMAT JSON) ${select} ${filter} ORDER BY attendance_records.attendance_date DESC`,parameters)).rows[0]['QUERY PLAN'];
    const patientPlan=(await query(`EXPLAIN (ANALYZE,BUFFERS,FORMAT JSON) ${select} ${filter} AND patient_id=$4 ORDER BY attendance_records.attendance_date DESC`,[...parameters,'scale-p-1'])).rows[0]['QUERY PLAN'];
    const nodes=(plan:any):any[]=>[plan,...(plan.Plans||[]).flatMap(nodes)];
    expect(nodes(before[0].Plan).some(node=>(node['Sort Key']||[]).some((key:string)=>key.includes('::text')))).toBe(true);
    expect(nodes(after[0].Plan).some(node=>(node['Sort Key']||[]).some((key:string)=>key.includes('::text')))).toBe(false);
    expect(after[0].Plan['Actual Rows']).toBe(300_000);
    expect(patientPlan[0].Plan['Actual Rows']).toBe(30);
    const patient=await request('/attendance?patientId=scale-p-1&kind=attendance&startDate=2026-01-01&endDate=2026-01-30');
    expect(patient.body).toHaveLength(30);
    expect(patient.body.every((row:any)=>row.patientId==='scale-p-1')).toBe(true);
    expect(patient.body.map((row:any)=>row.date)).toEqual(Array.from({length:30},(_,i)=>`2026-01-${String(30-i).padStart(2,'0')}`));
    const month=await request('/attendance?kind=attendance&startDate=2026-01-01&endDate=2026-01-30&format=map');
    expect(Object.keys(month.body)).toHaveLength(30);
    expect(Object.values(month.body).reduce((sum:number,day:any)=>sum+Object.keys(day).length,0)).toBe(300_000);
    expect(Object.keys(month.body)[0]).toBe('2026-01-30');
    expect(Object.keys(month.body)[29]).toBe('2026-01-01');
    const evidence={capturedAt:new Date().toISOString(),...seeded,before,after,patientPlan,
      patientRequest:{durationMs:rounded(patient.durationMs),bytes:patient.bytes,records:patient.body.length},
      monthRequest:{durationMs:rounded(month.durationMs),bytes:month.bytes,records:300_000},
      patientPlanIndexes:nodes(patientPlan[0].Plan).map(node=>node['Index Name']).filter(Boolean),
      note:'Native DATE sorting preserves date strings while avoiding the output text expression; broad reads still return all requested rows.'};
    await writeFile(new URL('scale-attendance.json',artifactDir),JSON.stringify(evidence,null,2));
    console.log('SCALE_ATTENDANCE',JSON.stringify({...evidence,before:before[0]['Execution Time'],after:after[0]['Execution Time'],patientPlan:patientPlan[0]['Execution Time']}));
  },180_000);
});
