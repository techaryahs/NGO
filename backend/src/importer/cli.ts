import path from 'path';
import { runFirebaseImport } from './index.js';

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  if (args.some((arg) => arg.startsWith('--') && !['--dry-run', '--apply', '--strict'].includes(arg)) ||
      (args.includes('--dry-run') && args.includes('--apply'))) {
    console.error('Usage: npm run import:firebase -- <export.json> [--dry-run | --apply] [--strict]');
    process.exitCode = 1;
    return;
  }
  const dryRun = !args.includes('--apply');
  const strict = args.includes('--strict');
  const fileArg = args.find((a) => !a.startsWith('--'));

  if (!fileArg || args.filter((a) => !a.startsWith('--')).length !== 1) {
    console.error('An explicit export path is required. Imports default to --dry-run; use --apply to commit.');
    process.exitCode = 1;
    return;
  }
  const targetFile = path.resolve(process.cwd(), fileArg);

  console.log('='.repeat(70));
  console.log('NGO Management System — Firebase RTDB to PostgreSQL Importer');
  console.log('='.repeat(70));
  console.log(`Source File : ${targetFile}`);
  console.log(`Dry Run     : ${dryRun ? 'YES (Database will NOT be modified)' : 'NO (Live Changes)'}`);
  console.log(`Strict Mode : ${strict ? 'YES' : 'NO'}`);
  console.log('='.repeat(70));

  try {
    const stats = await runFirebaseImport({
      filePath: targetFile,
      dryRun,
      strict,
      onProgress: (msg) => console.log(msg),
    });

    console.log('\n' + '='.repeat(70));
    console.log('IMPORT RECONCILIATION SUMMARY');
    console.log('='.repeat(70));
    console.log(`Duration: ${(stats.durationMs / 1000).toFixed(2)}s\n`);

    const printRow = (title: string, s: { processed: number; imported: number; updated: number; failed: number }) => {
      console.log(
        `${title.padEnd(20)} | Processed: ${String(s.processed).padStart(4)} | Inserted: ${String(s.imported).padStart(4)} | Updated: ${String(s.updated).padStart(4)} | Failed: ${String(s.failed).padStart(4)}`
      );
    };

    printRow('Rooms', stats.rooms);
    printRow('Beds', stats.beds);
    printRow('Patients', stats.patients);
    printRow('Attendants', stats.attendants);
    printRow('Stays', stats.stays);
    printRow('Attendance Records', stats.attendance);
    printRow('Payments', stats.payments);
    console.log(`Unchanged payments: ${stats.payments.unchanged}; deduplicated source copies: ${stats.payments.deduplicated}`);
    printRow('Photos', stats.photos);
    printRow('Expenses', stats.expenses);
    printRow('Sponsorships', stats.sponsorships);
    printRow('Settings', stats.settings);

    console.log('\n' + '-'.repeat(70));
    console.log('FINANCIAL RECONCILIATION');
    console.log('-'.repeat(70));
    console.log(
      `Source Total Payments  : ₹${stats.financials.sourceTotalPayments.toLocaleString('en-IN', { minimumFractionDigits: 2 })}`
    );
    console.log(
      `Transaction Payments   : ₹${stats.financials.dbTotalPayments.toLocaleString('en-IN', { minimumFractionDigits: 2 })}`
    );
    console.log(
      `Source Patient Paid    : ₹${stats.financials.sourceTotalPatientPaid.toLocaleString('en-IN', { minimumFractionDigits: 2 })}`
    );
    console.log(
      `Transaction Patient Paid: ₹${stats.financials.dbTotalPatientPaid.toLocaleString('en-IN', { minimumFractionDigits: 2 })}`
    );
    console.log(
      `Source Patient Due     : ₹${stats.financials.sourceTotalPatientDue.toLocaleString('en-IN', { minimumFractionDigits: 2 })}`
    );
    console.log(
      `Transaction Patient Due: ₹${stats.financials.dbTotalPatientDue.toLocaleString('en-IN', { minimumFractionDigits: 2 })}`
    );

    if (stats.warnings.length > 0) {
      console.log('\n' + '-'.repeat(70));
      console.log(`WARNINGS / DISCREPANCIES (${stats.warnings.length} issues)`);
      console.log('-'.repeat(70));
      for (const w of stats.warnings.slice(0, 10)) {
        console.log(` • ${w}`);
      }
      if (stats.warnings.length > 10) {
        console.log(` ... and ${stats.warnings.length - 10} more warnings.`);
      }
    }

    console.log('='.repeat(70));
    console.log(`Committed: ${stats.committed ? 'YES' : 'NO'}`);
    if (!stats.committed) console.log('Counts and transaction totals above are a preview; no imported writes were retained.');
    process.exit(stats.committed ? 0 : 2);
  } catch (err: unknown) {
    // Database exceptions may contain patient payloads or connection details.
    console.error('\n[FATAL] Import failed and was rolled back. Review the source and database configuration.');
    process.exit(1);
  }
}

main();
