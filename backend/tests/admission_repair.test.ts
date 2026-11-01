import { afterEach, expect, it, vi } from 'vitest';
import * as db from '../src/db/index.js';
import { startAdmissionRepair } from '../src/services/admission_repair.js';

afterEach(() => { vi.useRealTimers(); vi.restoreAllMocks(); });

it('registers startup and hourly repair, then stops its timer on shutdown', async () => {
  vi.useFakeTimers();
  const query = vi.spyOn(db, 'query').mockResolvedValue({ rows: [], rowCount: 0 } as any);
  const log = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };
  const stop = startAdmissionRepair(log);
  await vi.advanceTimersByTimeAsync(0);
  expect(query).toHaveBeenCalledTimes(1);
  expect(log.info).toHaveBeenCalledWith({ event: 'admission_repair_registered', intervalMs: 3600000, runOnStartup: true }, 'Admission repair job registered');
  await vi.advanceTimersByTimeAsync(3600000);
  expect(query).toHaveBeenCalledTimes(2);
  await stop();
  await vi.advanceTimersByTimeAsync(3600000);
  expect(query).toHaveBeenCalledTimes(2);
});

it('does not overlap repair runs and logs startup query failures', async () => {
  vi.useFakeTimers();
  let reject!: (reason: Error) => void;
  const query = vi.spyOn(db, 'query').mockImplementationOnce(() => new Promise((_, fail) => { reject = fail; }));
  const log = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };
  const stop = startAdmissionRepair(log);
  await vi.advanceTimersByTimeAsync(3600000);
  expect(query).toHaveBeenCalledTimes(1);
  reject(new Error('Unavailable'));
  await stop();
  expect(log.error).toHaveBeenCalledWith(expect.objectContaining({ event: 'admission_repair_failed' }), 'Admission repair run failed');
});
