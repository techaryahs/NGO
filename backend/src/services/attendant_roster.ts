import { httpError } from '../validation.js';

const calendar = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Kolkata', year: 'numeric', month: '2-digit', day: '2-digit' });
const day = (value: any) => calendar.format(new Date(value));

/** Association metadata lives with the admission's existing attendant snapshot.
 * Existing snapshots without dates retain their historical meaning. New people
 * start on their actual association day; edits/retries never move that day.
 */
export function admissionRoster(people: any[], previous: any[], patient: any, now = Date.now()) {
  const admission = day(patient.admission_date);
  return people.map(person => {
    const old = previous.find(p => p.id === person.id);
    const startDate = old?.startDate ?? (old ? undefined : person.startDate ?? (day(now) < admission ? admission : day(now)));
    if (startDate != null && (!/^\d{4}-\d{2}-\d{2}$/.test(startDate) ||
        !Number.isFinite(Date.parse(startDate)) || new Date(startDate).toISOString().slice(0, 10) !== startDate ||
        startDate < admission || (patient.exit_date && startDate > day(patient.exit_date)))) {
      throw httpError(400, 'Attendant arrival date must be a valid date within this admission');
    }
    const { photoDataUrl, startDate: requestedStart, endDate: requestedEnd, ...metadata } = person;
    return { ...old, ...metadata, ...(startDate != null ? { startDate } : {}) };
  });
}

export function eligibleAttendant(person: any, date: string): boolean {
  return (!person.startDate || date >= person.startDate) && (!person.endDate || date <= person.endDate);
}
