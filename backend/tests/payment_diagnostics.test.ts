import { afterEach, describe, expect, it, vi } from 'vitest';
import { buildApp } from '../src/app.js';
import * as db from '../src/db/index.js';
import { installTestFirebaseKeys, signedTestToken } from './helpers/auth.js';

describe('safe payment request diagnostics', () => {
  afterEach(() => vi.restoreAllMocks());
  it('correlates failed submission without logging references, tokens or raw database details', async () => {
    installTestFirebaseKeys();
    const lines: string[] = [];
    const app = buildApp({ logger: { level:'info', stream: { write: (line: string) => { lines.push(line); } } } });
    vi.spyOn(db,'query').mockResolvedValue({ rows:[{id:'test-uid-admin',email:'synthetic',name:'Synthetic',role:'admin'}],rowCount:1 } as any);
    vi.spyOn(db,'getClient').mockResolvedValue({
      query:vi.fn(async (sql:string) => {
        if (sql.includes('FOR UPDATE')) throw Object.assign(new Error('raw database UTR secretreference123 and secret-credential'), {code:'23505'});
        return {rows:[],rowCount:0};
      }), release:vi.fn(),
    } as any);
    const token = signedTestToken();
    try {
      const response = await app.inject({method:'POST',url:'/api/payments',headers:{authorization:`Bearer ${token}`,'x-request-id':'payreq_diagnostic_test'},
        payload:{id:'synthetic-request',patientId:'synthetic-patient',amount:2400,transactionId:'secretreference123'}});
      expect(response.statusCode).toBe(409);
      expect(response.headers['x-request-id']).toBe('payreq_diagnostic_test');
      expect(response.json().requestId).toBe('payreq_diagnostic_test');
      const logs = lines.join('');
      expect(logs).toContain('payreq_diagnostic_test');
      expect(logs).toContain('payment_conflict');
      expect(logs).toContain('payment_submission');
      expect(logs).toContain('409');
      for (const secret of ['secretreference123','secret-credential',token,'raw database']) expect(logs).not.toContain(secret);
    } finally { await app.close(); }
  });
});
