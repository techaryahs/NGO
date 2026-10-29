import type pg from 'pg';
import { pool } from '../src/db/index.js';
import { projectBilling, persistBilling, normalizeExitDate } from '../src/services/billing.js';

export interface RepairPatientResult {
  patientId: string;
  name: string;
  oldTotal: number;
  newTotal: number;
  action: string;
}

export interface DischargeCandidate {
  patientId: string;
  name: string;
  admissionDate: string;
  lastAttendance: string | null;
}

export interface RepairBillingReport {
  dryRun: boolean;
  activePatientsProcessed: number;
  patientsUpdated: number;
  patientsUnchanged: number;
  patients: RepairPatientResult[];
  dischargeCandidates: DischargeCandidate[];
}

export async function repairBilling(
  client: pg.PoolClient,
  options: { dryRun?: boolean; asOf?: number } = {}
): Promise<RepairBillingReport> {
  const dryRun = options.dryRun ?? true;
  const now = options.asOf ? new Date(options.asOf) : new Date();

  // 1. Query all ACTIVE stays for ACTIVE patients only.
  // Already-discharged stays and frozen invoices are NEVER selected or modified.
  const activePatientsRes = await client.query(`
    SELECT DISTINCT p.* 
    FROM patients p
    JOIN stays s ON s.patient_id = p.id
    WHERE p.status = 'active' AND s.status = 'active'
    ORDER BY p.id
  `);

  const results: RepairPatientResult[] = [];
  let updatedCount = 0;
  let unchangedCount = 0;

  for (const patient of activePatientsRes.rows) {
    const oldTotal = Number(patient.advance_billed_amount ?? 0);
    const hasPlannedExit = patient.exit_date != null;
    const isPastPlannedExit = hasPlannedExit && normalizeExitDate(patient.exit_date) < now;

    // Recompute billing under new rules (strict attendance, planned exit cutoff)
    const projection = await projectBilling(client, patient, { asOf: now.getTime() });
    const newTotal = Number(projection.patient.advance_billed_amount ?? 0);

    let action: string;
    if (isPastPlannedExit) {
      action = 'billing capped at planned exit, awaiting manual discharge';
      if (!dryRun) {
        await persistBilling(client, projection);
      }
      if (Math.abs(oldTotal - newTotal) > 0.001) {
        updatedCount++;
      } else {
        unchangedCount++;
      }
    } else if (Math.abs(oldTotal - newTotal) > 0.001) {
      action = dryRun ? 'would recompute billing' : 'recomputed billing';
      if (!dryRun) {
        await persistBilling(client, projection);
      }
      updatedCount++;
    } else {
      action = 'unchanged';
      unchangedCount++;
    }

    results.push({
      patientId: patient.id,
      name: patient.name ?? 'Unnamed',
      oldTotal,
      newTotal,
      action,
    });
  }

  // 2. Query ACTIVE stays with no planned exit date and no attendance marked in last 3 days
  const threeDaysAgoStr = new Date(now.getTime() - 3 * 86400000).toISOString().slice(0, 10);
  const candidatesRes = await client.query(`
    SELECT p.id, p.name, p.admission_date::text as admission_date, MAX(a.attendance_date::text) as last_attendance
    FROM patients p
    JOIN stays s ON s.patient_id = p.id
    LEFT JOIN attendance_records a ON a.patient_id = p.id
    WHERE p.status = 'active' AND s.status = 'active' AND p.exit_date IS NULL
    GROUP BY p.id, p.name, p.admission_date
    HAVING MAX(a.attendance_date::text) IS NULL OR MAX(a.attendance_date::text) < $1
    ORDER BY p.id
  `, [threeDaysAgoStr]);

  const dischargeCandidates: DischargeCandidate[] = candidatesRes.rows.map((r: any) => ({
    patientId: r.id,
    name: r.name ?? 'Unnamed',
    admissionDate: r.admission_date ?? 'Unknown',
    lastAttendance: r.last_attendance ?? null,
  }));

  return {
    dryRun,
    activePatientsProcessed: activePatientsRes.rows.length,
    patientsUpdated: updatedCount,
    patientsUnchanged: unchangedCount,
    patients: results,
    dischargeCandidates,
  };
}

export function formatReport(report: RepairBillingReport): string {
  const lines: string[] = [];
  lines.push('='.repeat(78));
  lines.push('NGO Management System — Billing Engine Repair Script');
  lines.push('='.repeat(78));
  lines.push(`Mode   : ${report.dryRun ? 'DRY RUN (no database changes will be written)' : 'LIVE APPLY (changes committed to database)'}`);
  lines.push('Target : Active stays only (Discharged stays / frozen invoices are untouched)');
  lines.push('='.repeat(78));
  lines.push('');
  lines.push('PATIENT BILLING RECOMPUTATION REPORT:');
  lines.push('-'.repeat(78));
  lines.push(
    `${'Patient ID'.padEnd(14)} | ${'Name'.padEnd(20)} | ${'Old Total'.padStart(10)} | ${'New Total'.padStart(10)} | Action`
  );
  lines.push('-'.repeat(78));

  if (report.patients.length === 0) {
    lines.push('No active patients found.');
  } else {
    for (const p of report.patients) {
      const oldStr = `₹${p.oldTotal.toFixed(2)}`;
      const newStr = `₹${p.newTotal.toFixed(2)}`;
      lines.push(
        `${p.patientId.padEnd(14)} | ${p.name.slice(0, 20).padEnd(20)} | ${oldStr.padStart(10)} | ${newStr.padStart(10)} | ${p.action}`
      );
    }
  }

  lines.push('-'.repeat(78));
  lines.push(
    `Summary: ${report.activePatientsProcessed} active patients processed (${report.patientsUpdated} ${report.dryRun ? 'would update' : 'updated'}, ${report.patientsUnchanged} unchanged).`
  );
  lines.push('');
  lines.push('MANUAL-DISCHARGE CANDIDATES (Report Only):');
  lines.push('Active stays with no planned exit date and no attendance marked in last 3 days:');
  lines.push('-'.repeat(78));
  lines.push(
    `${'Patient ID'.padEnd(14)} | ${'Name'.padEnd(20)} | ${'Admission Date'.padEnd(14)} | Last Attendance`
  );
  lines.push('-'.repeat(78));

  if (report.dischargeCandidates.length === 0) {
    lines.push('No manual discharge candidates found.');
  } else {
    for (const c of report.dischargeCandidates) {
      lines.push(
        `${c.patientId.padEnd(14)} | ${c.name.slice(0, 20).padEnd(20)} | ${(c.admissionDate || 'N/A').padEnd(14)} | ${c.lastAttendance ?? 'None'}`
      );
    }
  }

  lines.push('-'.repeat(78));
  lines.push(`Total candidates: ${report.dischargeCandidates.length}`);
  lines.push('='.repeat(78));
  return lines.join('\n');
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  if (args.includes('--help') || args.includes('-h')) {
    console.log('Usage: npx tsx scripts/repair-billing.ts [--dry-run | --apply]');
    return;
  }
  const dryRun = !args.includes('--apply');

  const client = await pool.connect();
  try {
    if (!dryRun) {
      await client.query('BEGIN');
    }
    const report = await repairBilling(client, { dryRun });
    if (!dryRun) {
      await client.query('COMMIT');
    }
    console.log(formatReport(report));
  } catch (err) {
    if (!dryRun) {
      await client.query('ROLLBACK');
    }
    console.error('Repair script failed:', err);
    process.exitCode = 1;
  } finally {
    client.release();
    await pool.end();
  }
}

// Only invoke main when executed directly as CLI
const isDirectCli = process.argv[1]?.replace(/\\/g, '/').endsWith('backend/scripts/repair-billing.ts');
if (isDirectCli) {
  main().catch((err) => {
    console.error('Fatal repair script error:', err);
    process.exit(1);
  });
}
