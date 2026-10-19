import { createHash } from 'node:crypto';

export function attendantId(patientId: string, index: number): string {
  const legacy = `att_${patientId}_${index}`;
  return legacy.length <= 64 ? legacy : `att_${createHash('sha256').update(legacy).digest('hex').slice(0, 60)}`;
}
