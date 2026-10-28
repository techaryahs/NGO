// Offline dry run only. Input: { patients: database-shaped rows,
// stays: database-shaped rows, receipts: database-shaped rows }.
// Never connects to a database or rewrites source records.
import { readFileSync } from 'node:fs';
import { receiptCycle, stayCycle, money } from '../src/services/billing.js';

const input = JSON.parse(readFileSync(process.argv[2], 'utf8'));
// The schema-verified export already has pseudonymous cycle identities. Never
// parse those tokens as admission timestamps or feed them to date fallbacks.
if (input.metadata?.format_version === 1 && input.records) {
  const data = input.records;
  const report = data.patients.map((patient: any) => {
    const known = new Set([patient.current_cycle_id, ...Object.keys(patient.admission_balances ?? {}),
      ...data.stays.filter((s: any) => s.patient_id === patient.id && s.status !== 'cancelled')
        .map((s: any) => s.cycle_id ?? s.snapshot?.cycle_id).filter(Boolean)]);
    return { patientId: patient.id, receipts: data.payments.filter((r: any) => r.patient_id === patient.id).map((r: any) => ({
      id: r.id, amount: r.amount, originalCycle: r.cycle_id,
      resolvedCycle: r.cycle_id != null && known.has(r.cycle_id) ? r.cycle_id : null,
      reason: r.cycle_id == null ? 'unresolved_missing_cycle' : known.has(r.cycle_id) ? 'matched' : 'unknown_cycle',
    })) };
  });
  process.stdout.write(JSON.stringify({ mode: 'dry-run-pseudonymous-export', patients: report }, null, 2) + '\n');
  process.exit(0);
}
const seen = new Set<string>();
for (const row of input.receipts) {
  if (!row.id || seen.has(row.id)) throw new Error('Missing or duplicate receipt ID; review source before reconciliation');
  seen.add(row.id);
}
const report = input.patients.map((patient: any) => {
  const stays = input.stays.filter((s: any) => s.patient_id === patient.id && s.status !== 'cancelled');
  const known = new Set([String(new Date(patient.admission_date).getTime()), ...stays.map((s: any) => stayCycle(s, patient)), ...Object.keys(patient.admission_balances ?? {})]);
  const receipts = input.receipts.filter((r: any) => r.patient_id === patient.id);
  return {
    patientId: patient.id,
    netPayments: receipts.reduce((sum: number, r: any) => sum + money(r.amount), 0) / 100,
    receipts: receipts.map((r: any) => {
      const cycle = receiptCycle(r, patient, stays);
      return { id: r.id, amount: money(r.amount) / 100, originalCycle: r.cycle_id ?? null,
        resolvedCycle: cycle != null && known.has(cycle) ? cycle : null,
        reason: cycle == null ? 'ambiguous' : known.has(cycle) ? 'matched' : 'unknown_cycle' };
    }),
  };
});
process.stdout.write(JSON.stringify({ mode: 'dry-run', patients: report }, null, 2) + '\n');
