import { readFileSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const audit = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(audit,'../..');
const read = name => readFileSync(path.join(audit,name),'utf8');
const checks = {};
function check(name, value) { checks[name] = Boolean(value); if (!value) throw new Error(name); }
const git = args => spawnSync('git',args,{cwd:root,encoding:'utf8',windowsHide:true});
try {
  const baseline = git(['rev-parse','HEAD']);
  check('specified-deployed-baseline',baseline.status === 0 && baseline.stdout.trim() === 'b2beb0828f70e5ecc46897b2d534e0b4386394e7');
  const matrix = read('postgres-matrix.txt');
  const counts = [...matrix.matchAll(/Tests\s+(\d+) passed \(\d+\)/g)].map(match=>Number(match[1]));
  check('all-nine-database-suites-ran',counts.length === 10 && matrix.includes('DISPOSABLE_MATRIX_COMPLETE: all suites executed; no opt-in files skipped'));
  check('180-unit-192-postgresql-tests',counts[0] === 180 && counts.slice(1).reduce((a,b)=>a+b,0) === 192);
  check('508-flutter-tests',read('flutter-all.txt').includes('+508: All tests passed!') && !read('flutter-all.txt').includes('[E]'));
  check('real-http-database-exact-workflow',read('flutter-all.txt').includes('3800 General bill: partial 1400 and remaining 2400 through real Flutter services'));
  check('blank-dialog-and-recovery-tests',read('flutter-all.txt').includes('cancel and reopen clear UTR and receipt') && read('flutter-all.txt').includes('retry clears the error and loads the current due'));
  check('static-analysis-clean',read('flutter-analyze.txt').includes('No issues found!'));
  check('windows-build',/Built build\\windows\\x64\\runner\\Release\\ngo.exe/.test(read('flutter-build.txt')));
  check('backend-build',read('backend-build.txt').includes('> tsc') && !/error TS\d+/.test(read('backend-build.txt')));
  const protectedFiles = git(['diff','--name-only','--','backend/src/services/billing.ts','lib/utils/stay_billing.dart','lib/utils/pricing_helper.dart','backend/migrations','backend/src/routes/attendance.ts','backend/src/routes/stays.ts']);
  check('billing-attendance-and-schema-unchanged',protectedFiles.status === 0 && protectedFiles.stdout.trim() === '');
  const diff = git(['diff','--check']);
  check('diff-check',diff.status === 0);
  const result = {verdict:'PASS',backendUnit:180,postgresIntegration:192,flutter:508,checks};
  writeFileSync(path.join(root,'.gravitas/sessions/remaining-payment-20261022/verification.json'),JSON.stringify(result,null,2)+'\n');
  console.log(JSON.stringify(result,null,2));
  console.log('VERDICT: PASS');
} catch (error) { console.error(`VERDICT: FAIL -- ${error.message}`); process.exitCode=1; }
