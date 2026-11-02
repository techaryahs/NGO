import { describe, expect, it } from 'vitest';
import { admissionRoster, eligibleAttendant } from '../src/services/attendant_roster.js';

const patient = { admission_date: '2026-10-01', exit_date: '2026-10-10' };
const helper = { id: 'stable-person', name: 'Synthetic helper' };
describe('admission attendant associations', () => {
  it('defaults a new association to the episode admission day', () => {
    const result = admissionRoster([helper], [], patient);
    expect(result[0].startDate).toBe('2026-10-01');
    expect(eligibleAttendant(result[0], '2026-10-01')).toBe(true);
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
  it('defaults a new association to admission despite an earlier planned exit', () => {
    expect(admissionRoster([helper], [], { ...patient, discharge_date: null }))
      .toEqual([{ ...helper, startDate: '2026-10-01' }]);
  });
  it('accepts an explicit new arrival after the planned exit while still admitted', () => {
    expect(admissionRoster([{ ...helper, startDate: '2026-10-12' }], [], patient))
      .toEqual([{ ...helper, startDate: '2026-10-12' }]);
  });
  it('rejects a new arrival after the actual discharge day with 400', () => {
    expect(() => admissionRoster([{ ...helper, startDate: '2026-10-13' }], [], {
      ...patient, discharge_date: '2026-10-11T20:00:00Z',
    })).toThrow(expect.objectContaining({ statusCode: 400, message: 'Attendant arrival date must be a valid date within this admission' }));
  });
  it('accepts a new arrival on the IST discharge day, including after the planned exit', () => {
    expect(admissionRoster([{ ...helper, startDate: '2026-10-12' }], [], {
      ...patient, discharge_date: '2026-10-11T20:00:00Z',
    })).toEqual([{ ...helper, startDate: '2026-10-12' }]);
  });
  it('compares the lower bound with the IST admission day', () => {
    const admitted = { ...patient, admission_date: '2026-10-01T20:00:00Z' };
    expect(() => admissionRoster([{ ...helper, startDate: '2026-10-01' }], [], admitted))
      .toThrow(expect.objectContaining({ statusCode: 400 }));
    expect(admissionRoster([{ ...helper, startDate: '2026-10-02' }], [], admitted))
      .toEqual([{ ...helper, startDate: '2026-10-02' }]);
  });
  it('defaults from the patient admission without a clock argument', () => {
    expect(admissionRoster([helper], [], patient))
      .toEqual([{ ...helper, startDate: '2026-10-01' }]);
  });
  it('preserves an existing arrival after the planned exit alongside an unrelated edit', () => {
    const old = [{ ...helper, startDate: '2026-10-12' }];
    expect(admissionRoster(old, old, { ...patient, medical_condition: 'Updated condition' })).toEqual(old);
  });
  it.each(['2026-09-30', '2026-10-13', '2026-13-40', '10/05/2026'])('accepts existing stored arrival %s without revalidation', startDate => {
    const old = [{ ...helper, startDate }];
    expect(admissionRoster([{ ...helper, startDate: '2026-10-05' }], old, {
      ...patient, discharge_date: '2026-10-12',
    })).toEqual(old);
  });
  it.each(['2026-02-30', '2026-09-30', '2026-13-40', '10/05/2026', 'invalid'])('rejects invalid new arrival %s with 400', startDate => {
    expect(() => admissionRoster([{ ...helper, startDate }], [], patient))
      .toThrow(expect.objectContaining({ statusCode: 400, message: 'Attendant arrival date must be a valid date within this admission' }));
  });
  it('retains departure bounds and omits inline photos', () => {
    const old = [{ ...helper, startDate: '2026-10-06', endDate: '2026-10-08' }];
    const result = admissionRoster([{ ...helper, photoDataUrl: 'synthetic' }], old, patient);
    expect(result[0]).not.toHaveProperty('photoDataUrl');
    expect(eligibleAttendant(result[0], '2026-10-09')).toBe(false);
  });
});
