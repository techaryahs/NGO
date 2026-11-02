import { httpError } from '../validation.js';

const calendar = new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Kolkata', year: 'numeric', month: '2-digit', day: '2-digit' });
const day = (value: any) => calendar.format(new Date(value));

/** Association metadata lives with the admission's existing attendant snapshot.
 * Existing snapshots without dates retain their historical meaning. New people
 * default to the episode admission day; edits/retries never move stored dates.
 */
export function admissionRoster(people: any[], previous: any[], patient: any) {
  const admission = day(patient.admission_date);
  const entryDay = day(Date.now());
  return people.map(person => {
    const old = previous.find(p => p.id === person.id);
    const presentedStart = person.startDate === entryDay && admission < entryDay ? undefined : person.startDate;
    const startDate = old?.startDate ?? (old ? undefined : presentedStart ?? admission);
    if (!old && startDate != null && (!/^\d{4}-\d{2}-\d{2}$/.test(startDate) ||
        !Number.isFinite(Date.parse(startDate)) || new Date(startDate).toISOString().slice(0, 10) !== startDate ||
        startDate < admission || (patient.discharge_date && startDate > day(patient.discharge_date)))) {
      throw httpError(400, 'Attendant arrival date must be a valid date within this admission');
    }
    const { photoDataUrl, startDate: requestedStart, endDate: requestedEnd, ...metadata } = person;
    return { ...old, ...metadata, ...(startDate != null ? { startDate } : {}) };
  });
}

export function eligibleAttendant(person: any, date: string): boolean {
  return (!person.startDate || date >= person.startDate) && (!person.endDate || date <= person.endDate);
}
