import { describe, expect, it } from 'vitest';
import type pg from 'pg';
import { repairBilling, formatReport } from '../scripts/repair-billing.js';

const pricing = {
  generalRoomBedPrice: 200,
  privateRoomBasePrice: 700,
  privateRoomIncludedAttendants: 1,
  privateRoomExtraAttendantFee: 200,
};

describe('repair-billing script unit tests', () => {
  it('recomputes billing for active stays, caps at planned exit, leaves discharged patients untouched, and is idempotent', async () => {
    // 1. Mock DB state
    const patients: Record<string, any> = {
      // Active patient with passed planned exit (Oct 25). Admitted Oct 21. Present Oct 21-28.
      p_capped: {
        id: 'p_capped',
        name: 'Capped Patient',
        status: 'active',
        admission_date: '2026-10-21T03:30:00.000Z',
        registration_date: '2026-10-21T03:30:00.000Z',
        exit_date: '2026-10-25T18:29:59.999Z', // Oct 25 end of day IST
        advance_billed_amount: '3200.00', // old provisional was for 8 days (8 * 400 = 3200)
        attendants: [{ name: 'Attendant 1' }],
      },
      // Active patient with no planned exit, no attendance in last 3 days (Oct 29 view, last attendance Oct 22)
      p_candidate: {
        id: 'p_candidate',
        name: 'Candidate Patient',
        status: 'active',
        admission_date: '2026-10-21T03:30:00.000Z',
        registration_date: '2026-10-21T03:30:00.000Z',
        exit_date: null,
        advance_billed_amount: '3600.00',
        attendants: [{ name: 'Attendant 1' }],
      },
      // Discharged patient with frozen invoice
      p_discharged: {
        id: 'p_discharged',
        name: 'Discharged Patient',
        status: 'discharged',
        discharge_date: '2026-10-20T03:30:00.000Z',
        admission_date: '2026-10-10T03:30:00.000Z',
        registration_date: '2026-10-10T03:30:00.000Z',
        exit_date: '2026-10-20T03:30:00.000Z',
        advance_billed_amount: '5000.00',
        attendants: [],
      },
    };

    const stays: Record<string, any[]> = {
      p_capped: [
        {
          id: 'stay_capped',
          patient_id: 'p_capped',
          status: 'active',
          room_type: 'general',
          admission_date: '2026-10-21T03:30:00.000Z',
          expected_discharge_date: '2026-10-25T18:29:59.999Z',
          cycle_id: String(new Date('2026-10-21T03:30:00.000Z').getTime()),
          total_cost: '3200.00',
        },
      ],
      p_candidate: [
        {
          id: 'stay_candidate',
          patient_id: 'p_candidate',
          status: 'active',
          room_type: 'general',
          admission_date: '2026-10-21T03:30:00.000Z',
          expected_discharge_date: null,
          cycle_id: String(new Date('2026-10-21T03:30:00.000Z').getTime()),
          total_cost: '3600.00',
        },
      ],
      p_discharged: [
        {
          id: 'stay_discharged',
          patient_id: 'p_discharged',
          status: 'completed',
          room_type: 'general',
          admission_date: '2026-10-10T03:30:00.000Z',
          expected_discharge_date: '2026-10-20T03:30:00.000Z',
          completed_at: '2026-10-20T03:30:00.000Z',
          cycle_id: String(new Date('2026-10-10T03:30:00.000Z').getTime()),
          total_cost: '5000.00',
        },
      ],
    };

    const attendanceRecords: Record<string, any[]> = {
      p_capped: [
        // Oct 21-28 present (both patient and attendant = 400/day)
        ...Array.from({ length: 8 }, (_, i) => [
          { kind: 'attendance', attendance_date: `2026-10-${21 + i}`, payload: { status: 'Present' } },
          { kind: 'attendant_attendance', attendance_date: `2026-10-${21 + i}`, payload: { attendantName: 'Attendant 1', status: 'Present' } },
        ]).flat(),
      ],
      p_candidate: [
        // Only Oct 21-22 marked Present (400/day = 800 total). No marks after Oct 22.
        { kind: 'attendance', attendance_date: '2026-10-21', payload: { status: 'Present' } },
        { kind: 'attendant_attendance', attendance_date: '2026-10-21', payload: { attendantName: 'Attendant 1', status: 'Present' } },
        { kind: 'attendance', attendance_date: '2026-10-22', payload: { status: 'Present' } },
        { kind: 'attendant_attendance', attendance_date: '2026-10-22', payload: { attendantName: 'Attendant 1', status: 'Present' } },
      ],
      p_discharged: [],
    };

    const createMockClient = () => {
      return {
        query: async (sql: string, params: any[] = []) => {
          // Query active patients
          if (sql.includes('SELECT DISTINCT p.*')) {
            const rows = Object.values(patients).filter(p => p.status === 'active' && stays[p.id]?.some(s => s.status === 'active'));
            return { rows };
          }
          // Query discharge candidates
          if (sql.includes('HAVING MAX(a.attendance_date::text) IS NULL OR MAX(a.attendance_date::text) < $1')) {
            const cutoffDate = params[0]; // e.g. 2026-10-26
            const rows: any[] = [];
            for (const p of Object.values(patients)) {
              if (p.status === 'active' && !p.exit_date) {
                const records = attendanceRecords[p.id] ?? [];
                const dates = records.map(r => r.attendance_date).sort();
                const maxDate = dates.length ? dates[dates.length - 1] : null;
                if (!maxDate || maxDate < cutoffDate) {
                  rows.push({
                    id: p.id,
                    name: p.name,
                    admission_date: p.admission_date,
                    last_attendance: maxDate,
                  });
                }
              }
            }
            return { rows };
          }
          // Stays for a patient
          if (sql.includes('FROM stays WHERE patient_id=$1')) {
            const patientId = params[0];
            return { rows: stays[patientId] ?? [] };
          }
          // Attendance records for a patient
          if (sql.includes('FROM attendance_records WHERE patient_id=$1')) {
            const patientId = params[0];
            const rows = (attendanceRecords[patientId] ?? []).map(r => ({
              kind: r.kind,
              day: r.attendance_date,
              payload: r.payload,
            }));
            return { rows };
          }
          // Payments
          if (sql.includes('FROM payments WHERE patient_id=$1')) {
            return { rows: [] };
          }
          // Corrections
          if (sql.includes('FROM billing_corrections WHERE patient_id=$1')) {
            return { rows: [] };
          }
          // System settings
          if (sql.includes('FROM system_settings')) {
            return { rows: Object.entries(pricing).map(([settings_key, settings_value]) => ({ settings_key, settings_value })) };
          }
          // Update patient (persistBilling)
          if (sql.startsWith('UPDATE patients SET')) {
            const patientId = params[0];
            patients[patientId].advance_billed_amount = params[1];
            return { rows: [patients[patientId]] };
          }
          // Update stays (persistBilling)
          if (sql.startsWith('UPDATE stays SET')) {
            return { rows: [] };
          }
          throw new Error(`Unexpected SQL: ${sql}`);
        },
      } as unknown as pg.PoolClient;
    };

    const asOf = new Date('2026-10-29T12:00:00.000Z').getTime();

    // 1. Dry run
    const client = createMockClient();
    const dryRunReport = await repairBilling(client, { dryRun: true, asOf });

    expect(dryRunReport.dryRun).toBe(true);
    expect(dryRunReport.activePatientsProcessed).toBe(2);
    // Discharged patient must NOT be in report
    expect(dryRunReport.patients.find(p => p.patientId === 'p_discharged')).toBeUndefined();

    // p_capped: planned exit Oct 25 has passed, 5 days (Oct 21-25) @ ₹400 = ₹2,000.
    const cappedResult = dryRunReport.patients.find(p => p.patientId === 'p_capped')!;
    expect(cappedResult).toBeDefined();
    expect(cappedResult.oldTotal).toBe(3200);
    expect(cappedResult.newTotal).toBe(2000); // exactly 5 days × ₹400
    expect(cappedResult.action).toBe('billing capped at planned exit, awaiting manual discharge');

    // p_candidate: only 2 days marked Present (Oct 21-22) @ ₹400 = ₹800.
    const candidateResult = dryRunReport.patients.find(p => p.patientId === 'p_candidate')!;
    expect(candidateResult).toBeDefined();
    expect(candidateResult.oldTotal).toBe(3600);
    expect(candidateResult.newTotal).toBe(800);
    expect(candidateResult.action).toBe('would recompute billing');

    // Check discharge candidates: p_candidate has last attendance Oct 22 (more than 3 days before Oct 29)
    expect(dryRunReport.dischargeCandidates).toHaveLength(1);
    expect(dryRunReport.dischargeCandidates[0].patientId).toBe('p_candidate');
    expect(dryRunReport.dischargeCandidates[0].lastAttendance).toBe('2026-10-22');

    // Ensure dry-run did NOT mutate DB records
    expect(patients.p_capped.advance_billed_amount).toBe('3200.00');

    // Test formatted output string
    const formatted = formatReport(dryRunReport);
    expect(formatted).toContain('billing capped at planned exit, awaiting manual discharge');
    expect(formatted).toContain('MANUAL-DISCHARGE CANDIDATES');
    expect(formatted).toContain('p_candidate');

    // 2. Apply run
    const applyReport = await repairBilling(client, { dryRun: false, asOf });
    expect(applyReport.dryRun).toBe(false);
    expect(applyReport.patientsUpdated).toBe(2);
    // Verified DB updated
    expect(patients.p_capped.advance_billed_amount).toBe('2000.00');
    expect(patients.p_candidate.advance_billed_amount).toBe('800.00');
    expect(patients.p_discharged.advance_billed_amount).toBe('5000.00'); // untouched

    // 3. Second run with apply (IDEMPOTENCY TEST)
    const secondReport = await repairBilling(client, { dryRun: false, asOf });
    expect(secondReport.patientsUpdated).toBe(0);
    expect(secondReport.patientsUnchanged).toBe(2);
    expect(secondReport.patients.every(p => p.action === 'unchanged' || p.action === 'billing capped at planned exit, awaiting manual discharge')).toBe(true);
  });
});
