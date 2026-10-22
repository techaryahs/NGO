import { describe, expect, it } from 'vitest';
import { admissionRoster, eligibleAttendant } from '../src/services/attendant_roster.js';

const patient = { admission_date: '2026-10-01', exit_date: '2026-10-10' };
const helper = { id: 'stable-person', name: 'Synthetic helper' };
describe('admission attendant associations', () => {
  it('defaults a new association to the actual Indian civil date, without backfill', () => {
    const result = admissionRoster([helper], [], patient, Date.parse('2026-10-05T20:00:00Z'));
    expect(result[0].startDate).toBe('2026-10-06');
    expect(eligibleAttendant(result[0], '2026-10-05')).toBe(false);
    expect(eligibleAttendant(result[0], '2026-10-06')).toBe(true);
  });
  it('preserves the valid start date and identity across edits and retries', () => {
    const old = [{ ...helper, startDate: '2026-10-06' }];
    const result = admissionRoster([{ ...helper, startDate: '2026-10-01', name: 'Corrected name' }], old, patient);
    expect(result).toEqual([{ ...helper, name: 'Corrected name', startDate: '2026-10-06' }]);
    expect(admissionRoster(result, result, patient)).toEqual(result);
  });
  it('does not turn a legacy full-admission association into a new dated association', () => {
    expect(admissionRoster([{ ...helper, startDate: 'invalid', endDate: 'invalid' }], [helper], patient)).toEqual([helper]);
  });
  it.each(['2026-02-30', '2026-09-30', '2026-10-11', 'invalid'])('rejects invalid new arrival %s', startDate => {
    expect(() => admissionRoster([{ ...helper, startDate }], [], patient)).toThrow('valid date within this admission');
  });
  it('retains departure bounds and omits inline photos', () => {
    const old = [{ ...helper, startDate: '2026-10-06', endDate: '2026-10-08' }];
    const result = admissionRoster([{ ...helper, photoDataUrl: 'synthetic' }], old, patient);
    expect(result[0]).not.toHaveProperty('photoDataUrl');
    expect(eligibleAttendant(result[0], '2026-10-09')).toBe(false);
  });
});
