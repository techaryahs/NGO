import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { buildApp } from '../src/app.js';
import { config } from '../src/config/index.js';
import { pool, query } from '../src/db/index.js';
import { runMigrations } from '../src/db/migrate.js';
import { installTestFirebaseKeys, signedTestToken } from './helpers/auth.js';
describe.skipIf(process.env.RUN_SETTLEMENT_TESTS !== '1')('isolated registration and settlement regressions', () => {
    const app = buildApp({ logger: false });
    const send = (method: any, url: string, payload?: any) => app.inject({ method, url: `/api${url}`, payload, headers: { authorization: `Bearer ${signedTestToken()}` } });
    const admission = '2026-10-19T06:12:00Z', exit = '2026-10-31T03:30:00Z';
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
        expect((await send('POST', '/patients/p1/discharge', {})).statusCode).toBe(409);
        expect((await query("SELECT status FROM stays WHERE id='s_p1'")).rows[0].status).toBe('active');
        const refund = { id: 'returned200', patientId: 'p1', cycleId: cycle, type: 'refund', amount: -200, method: 'cash' };
        expect((await send('POST', '/payments', refund)).statusCode).toBe(201);
        expect((await send('POST', '/payments', refund)).statusCode).toBe(200);
        const done = await send('POST', '/patients/p1/discharge', {});
        expect(done.statusCode).toBe(200);
        expect(done.json().patient).toMatchObject({ status: 'discharged', advanceBilledAmount: 2000, totalPaidAmount: 2000, totalRefundedAmount: 600, refundDueAmount: 0 });
        expect((await send('POST', '/patients/p1/discharge', {})).statusCode).toBe(200);
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
            pending = send('POST', '/patients/p1/discharge', {}).then(r => r);
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
            expect((await send('POST', '/patients/p1/discharge', {})).statusCode).toBe(500);
            expect((await query("SELECT status FROM patients WHERE id='p1'")).rows[0].status).toBe('active');
            expect((await query("SELECT status FROM stays WHERE id='s_p1'")).rows[0].status).toBe('active');
            expect((await query("SELECT current_patient_id FROM room_beds WHERE id='b1'")).rows[0].current_patient_id).toBe('p1');
        }
        finally {
            await query('DROP TRIGGER settlement_fail ON room_beds; DROP FUNCTION settlement_fail()');
        }
    });
    it.each(['2026-10-31T02:30:00Z', '2026-10-31T03:30:00Z', '2026-10-31T06:30:00Z'])('checkout at %s counts the same 13 calendar dates and does not fabricate presence', async (exitDate) => {
        await send('POST', '/patients/register', { ...patient(), exitDate, stays: [placement('s_p1')] });
        const before = (await send('GET', '/patients/p1/financials')).json().patient;
        expect(before).toMatchObject({ advanceBilledAmount: 2600, totalPresentDays: 0, totalAbsentDays: 0, refundDueAmount: 0 });
        expect((await query('SELECT id FROM attendance_records')).rows).toHaveLength(0);
        for (let d = 19; d <= 31; d++)
            await send('POST', '/attendance', { patientId: 'p1', date: `2026-10-${d}`, payload: { status: d >= 29 ? 'Absent' : 'Present' } });
        await send('POST', '/payments', { id: 'paid', patientId: 'p1', cycleId: cycle, amount: 2600, method: 'cash' });
        const marked = (await send('GET', '/patients/p1/financials')).json().patient;
        expect(marked).toMatchObject({ advanceBilledAmount: 2000, totalPresentDays: 10, totalAbsentDays: 3, refundDueAmount: 600 });
        await send('POST', '/payments', { id: 'refund', patientId: 'p1', cycleId: cycle, amount: -600, type: 'refund', method: 'cash' });
        const done = await send('POST', '/patients/p1/discharge', {});
        expect(done.statusCode).toBe(200);
        expect(done.json().patient).toMatchObject({ advanceBilledAmount: 2000, totalPaidAmount: 2000, refundDueAmount: 0 });
    });
    it('an undecided exit retains a seven-day advance and never creates attendance', async () => {
      await send('POST','/patients/register',{...patient(),exitDate:null,stays:[{...placement('s_p1'),durationDays:7}]});
      const result=(await send('GET','/patients/p1/financials')).json().patient;
      expect(result).toMatchObject({advanceBilledAmount:1400,totalPresentDays:0,totalAbsentDays:0,refundDueAmount:0});
      expect((await query('SELECT id FROM attendance_records')).rows).toHaveLength(0);
    });

    it('reading a closed legacy invoice and rejecting an excess refund preserves historical charges', async () => {
      await register();
      const saved={total:2000,paid:2600,refunded:600,netPaid:2000,due:0,refundDue:0,segmentCharges:{s_p1:2000},segmentDays:{s_p1:10}};
      await query("UPDATE patients SET status='discharged',advance_billed_amount=2000,total_paid_amount=2000,refund_due_amount=0,total_refunded_amount=600,admission_balances=$1::jsonb WHERE id='p1'",[JSON.stringify({[cycle]:saved})]);
      await query("UPDATE stays SET status='completed',completed_at=$1,total_cost=2400 WHERE id='s_p1'",[exit]);
      await query("INSERT INTO payments(id,patient_id,cycle_id,type,amount,payment_date) VALUES('legacy-paid','p1',$1,'payment',2600,CURRENT_TIMESTAMP),('legacy-refund','p1',$1,'refund',-600,CURRENT_TIMESTAMP)",[cycle]);
      const before=(await query("SELECT row_to_json(p) data FROM patients p WHERE id='p1'")).rows[0].data;
      expect((await send('GET','/patients/p1/financials')).json().patient).toMatchObject({advanceBilledAmount:2000,totalPaidAmount:2000,refundDueAmount:0});
      expect((await send('POST','/payments',{id:'over-refund',patientId:'p1',cycleId:cycle,type:'refund',amount:-200})).statusCode).toBe(409);
      expect((await query("SELECT row_to_json(p) data FROM patients p WHERE id='p1'")).rows[0].data).toEqual(before);
      expect((await query("SELECT total_cost::text FROM stays WHERE id='s_p1'")).rows[0].total_cost).toBe('2400.00');
    });

});
