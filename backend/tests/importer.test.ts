import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { runFirebaseImport } from '../src/importer/index.js';
import * as dbModule from '../src/db/index.js';
import { importerFixture } from './fixtures/importer-fixture.js';

describe('Firebase importer orchestration (mocked PostgreSQL)', () => {
  let directory: string;
  let fixture: Record<string, any>;
  let client: { query: ReturnType<typeof vi.fn>; release: ReturnType<typeof vi.fn> };
  const writeFixture = () => {
    const filePath = path.join(directory, 'synthetic.json');
    fs.writeFileSync(filePath, JSON.stringify(fixture));
    return filePath;
  };
  beforeEach(() => {
    directory = fs.mkdtempSync(path.join(os.tmpdir(), 'ngo-import-test-'));
    fixture = importerFixture();
    client = {
      query: vi.fn().mockImplementation(async (sql: string) => {
        if (sql.includes('SUM(amount)')) return { rows: [{ total: '0.30' }], rowCount: 1 };
        if (sql.includes('SUM(total_paid_amount)')) return { rows: [{ paid: '0.30', due: '9.70' }], rowCount: 1 };
        return { rows: [{ is_inserted: true }], rowCount: 1 };
      }), release: vi.fn(),
    };
    vi.spyOn(dbModule, 'getClient').mockResolvedValue(client as any);
  });
  afterEach(() => {
    vi.restoreAllMocks();
    fs.rmSync(directory, { recursive: true, force: true });
  });
  it('defaults to dry run, with exact source totals and canonical payment deduplication', async () => {
    const stats = await runFirebaseImport({ filePath: writeFixture(), onProgress: () => {} });
    expect(client.query).toHaveBeenCalledWith('BEGIN');
    expect(client.query).toHaveBeenCalledWith('ROLLBACK');
    expect(client.query).not.toHaveBeenCalledWith('COMMIT');
    expect(stats.committed).toBe(false);
    expect(stats.payments).toMatchObject({ processed: 2, imported: 2, failed: 0, deduplicated: 1 });
    expect(stats.attendance.imported).toBe(2);
    expect(stats.financials).toMatchObject({ sourceTotalPayments: 0.3, sourceTotalPatientPaid: 0.3, sourceTotalPatientDue: 9.7 });
  });
  it('rolls back and releases the connection on a fatal setup failure without logging payloads', async () => {
    client.query.mockRejectedValueOnce(new Error('connection failed'));
    await expect(runFirebaseImport({ filePath: writeFixture(), onProgress: () => {} })).rejects.toThrow('connection failed');
    expect(client.query).toHaveBeenCalledWith('ROLLBACK');
    expect(client.release).toHaveBeenCalledTimes(1);
  });
  it('rejects malformed roots before connecting', async () => {
    fs.writeFileSync(path.join(directory, 'invalid.json'), '[]');
    await expect(runFirebaseImport({ filePath: path.join(directory, 'invalid.json'), onProgress: () => {} })).rejects.toThrow('Export root');
    expect(dbModule.getClient).not.toHaveBeenCalled();
  });
  it('recovers a row SQL failure using a savepoint and redacts database detail', async () => {
    client.query.mockImplementation(async (sql: string) => {
      if (sql.includes('INSERT INTO patients')) throw Object.assign(new Error('sensitive patient payload'), { code: '23505' });
      return { rows: [{ is_inserted: true }], rowCount: 1 };
    });
    const stats = await runFirebaseImport({ filePath: writeFixture(), dryRun: false, onProgress: () => {} });
    expect(client.query).toHaveBeenCalledWith('ROLLBACK TO SAVEPOINT import_record');
    expect(stats.patients.failed).toBe(1);
    expect(stats.stays.missingPatientRefs).toBe(1);
    expect(stats.payments.missingPatientRefs).toBe(2);
    expect(stats.warnings.join(' ')).not.toContain('sensitive');
  });
  it.each(['12oops', 'NaN', 'Infinity', '0.001', '10000000000.00'])('rejects invalid money %s rather than truncating or rounding it', async (amount) => {
    fixture.payments = { invalid: { id: 'invalid', patientId: 'audit_patient', date: 1767261600000, amount } };
    fixture.paymentHistory = {};
    const stats = await runFirebaseImport({ filePath: writeFixture(), onProgress: () => {} });
    expect(stats.payments).toMatchObject({ processed: 1, failed: 1, imported: 0 });
  });
});
