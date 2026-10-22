// Evidence validator owned by this task's Gravitas contract. Read-only checks.
import { readFileSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const audit = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(audit, '../..');
const read = name => readFileSync(path.join(audit, name), 'utf8');
const checks = {};
const check = (name, condition) => {
  checks[name] = Boolean(condition);
  if (!condition) throw new Error(name);
};
try {
  const matrix = read('postgres-matrix.txt');
  const counts = [...matrix.matchAll(/Tests\s+(\d+) passed \(\d+\)/g)].map(match => Number(match[1]));
  check('all-nine-postgresql-suites-executed', matrix.includes('DISPOSABLE_MATRIX_COMPLETE: all suites executed; no opt-in files skipped') && counts.length === 10);
  check('179-unit-and-191-database-tests-passed', counts[0] === 179 && counts.slice(1).reduce((a,b) => a+b,0) === 191);
  check('503-flutter-tests-passed', /\+503: All tests passed!/.test(read('flutter-all.txt')) && !read('flutter-all.txt').includes('[E]'));
  check('both-real-flutter-lifecycle-variants-executed', [1,6].every(day => read('flutter-all.txt').includes(`attendee arrives day ${day}, attendance and remaining payment survive reload`)));
  check('actual-attendance-widget-passed', read('flutter-attendance-screen.txt').includes('+1: All tests passed!'));
  check('flutter-analysis-clean', read('flutter-analyze.txt').includes('No issues found!'));
  check('windows-release-built', /Built build\\windows\\x64\\runner\\Release\\ngo.exe/.test(read('flutter-build.txt')));
  check('typescript-build-recorded-without-errors', read('backend-build.txt').includes('> tsc') && !/error TS\d+/.test(read('backend-build.txt')));
  const git = args => spawnSync('git', args, { cwd: root, encoding: 'utf8', windowsHide: true });
  const before = git(['show', 'HEAD:backend/src/services/billing.ts']);
  check('baseline-tariff-readable', before.status === 0);
  const current = readFileSync(path.join(root,'backend/src/services/billing.ts'),'utf8');
  const tariffs = text => text.slice(text.indexOf('export function baseDailyChargeCents'),text.indexOf('export function stayCycle')).replaceAll('\r','');
  check('authoritative-daily-and-extension-tariffs-unchanged', tariffs(current) === tariffs(before.stdout));
  const diff = git(['diff','--check']);
  check('diff-whitespace-check', diff.status === 0);
  const result = { verdict: 'PASS', backendUnit: counts[0], postgresIntegration: counts.slice(1).reduce((a,b) => a+b,0), flutter: 503, checks };
  writeFileSync(path.join(root,'.gravitas/sessions/post-admission-20261022/verification.json'),JSON.stringify(result,null,2)+'\n');
  console.log(JSON.stringify(result,null,2));
  console.log('VERDICT: PASS');
} catch (error) {
  console.error(`VERDICT: FAIL -- ${error.message}`);
  process.exitCode = 1;
}
