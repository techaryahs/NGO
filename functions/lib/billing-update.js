'use strict';

const billing = require('./billing');

/**
 * Server-side port of PaymentService.billingUpdates (Flutter):
 * reads the patient, their stays, pricing and the attendance date ranges,
 * recomputes the admission balances and returns the multi-path RTDB update
 * map. The returned map is applied with one atomic `update()`.
 *
 * Returns { updates, balances, current, patient, staysList, pricing,
 *           attendance, attendantAttendance }.
 */

async function loadStays(db, patientId) {
  const snap = await db
    .ref('stays')
    .orderByChild('patientId')
    .equalTo(patientId)
    .once('value');
  const value = snap.val();
  if (!value || typeof value !== 'object') return [];
  return Object.entries(value)
    .filter(([, v]) => v && typeof v === 'object')
    .map(([key, v]) => ({ id: key, ...v }));
}

async function buildBillingUpdates(
  db,
  patientId,
  {
    patientData = null,
    stays = null,
    patientAttendanceOverrides = {},
    attendantAttendanceOverrides = {},
    nowMs = null,
  } = {},
) {
  const now = nowMs === null ? Date.now() : nowMs;
  const raw = patientData || (await db.ref(`patients/${patientId}`).once('value')).val();
  if (!raw || typeof raw !== 'object') {
    throw new Error(`Patient ${patientId} not found`);
  }
  const patient = raw;

  let staysList = stays;
  if (!staysList) {
    staysList = await loadStays(db, patientId);
  }

  // Older admissions stored the initial estimate as a fixed daily rate, which
  // prevents later attendance marks from reducing the bill. Only that
  // generated value is migrated back to a dynamic rate.
  const migratedDynamicRateIds = new Set();
  staysList = staysList.map((stay) => {
    const isGeneratedRate =
      (stay.costOverride === null || stay.costOverride === undefined) &&
      stay.dailyRateIsManual !== true &&
      stay.dailyRate !== null &&
      stay.dailyRate !== undefined;
    if (!isGeneratedRate) return stay;
    migratedDynamicRateIds.add(stay.id);
    return { ...stay, dailyRate: null };
  });

  const rangeStarts = [
    billing.toMs(
      patient.registrationDate !== null && patient.registrationDate !== undefined
        ? patient.registrationDate
        : patient.admissionDate,
      now,
    ),
    ...staysList.map((stay) => billing.toMs(stay.admissionDate, now)),
  ];
  const rangeEnds = [
    billing.toMs(
      patient.exitDate !== null && patient.exitDate !== undefined
        ? patient.exitDate
        : patient.dischargeDate !== null && patient.dischargeDate !== undefined
          ? patient.dischargeDate
          : now,
      now,
    ),
    ...staysList.map((stay) =>
      billing.toMs(
        stay.completedAt !== null && stay.completedAt !== undefined
          ? stay.completedAt
          : stay.expectedDischargeDate,
        now,
      ),
    ),
  ];
  rangeStarts.sort((a, b) => a - b);
  rangeEnds.sort((a, b) => a - b);
  const startKey = billing.dateKey(rangeStarts[0]);
  const endKey = billing.dateKey(rangeEnds[rangeEnds.length - 1]);

  const [pricingSnap, attendanceSnap, attendantSnap] = await Promise.all([
    db.ref('admin_settings/pricing').once('value'),
    db
      .ref('attendance/daily')
      .orderByKey()
      .startAt(startKey)
      .endAt(endKey)
      .once('value'),
    db
      .ref('attendant_attendance/daily')
      .orderByKey()
      .startAt(startKey)
      .endAt(endKey)
      .once('value'),
  ]);

  const rawPricing = pricingSnap.val();
  const pricing =
    rawPricing && typeof rawPricing === 'object' ? { ...rawPricing } : {};
  const savedGeneralRate = pricing['generalRoomBedPrice'];
  const migrateGeneralRate =
    savedGeneralRate === null ||
    savedGeneralRate === undefined ||
    Number(savedGeneralRate) === 150;
  if (migrateGeneralRate) pricing['generalRoomBedPrice'] = 200;

  // Patient attendance: { dateKey: status }.
  const attendance = {};
  const attendanceRecords = attendanceSnap.val();
  if (attendanceRecords && typeof attendanceRecords === 'object') {
    for (const [date, daily] of Object.entries(attendanceRecords)) {
      if (daily && typeof daily === 'object' && daily[patientId] && typeof daily[patientId] === 'object') {
        attendance[date] = String(daily[patientId].status || '');
      }
    }
  }
  for (const [date, value] of Object.entries(patientAttendanceOverrides)) {
    if (value === null || value === undefined) delete attendance[date];
    else attendance[date] = value;
  }

  // Attendant attendance: { dateKey: { attendantName: status } }.
  const attendantAttendance = {};
  const attendantRecords = attendantSnap.val();
  if (attendantRecords && typeof attendantRecords === 'object') {
    for (const [date, daily] of Object.entries(attendantRecords)) {
      if (!daily || typeof daily !== 'object') continue;
      const byPatient = daily[patientId];
      if (!byPatient || typeof byPatient !== 'object') continue;
      const statuses = {};
      for (const record of Object.values(byPatient)) {
        if (record && typeof record === 'object' && record.attendantName != null) {
          statuses[String(record.attendantName)] = String(record.status || '');
        }
      }
      attendantAttendance[date] = statuses;
    }
  }
  for (const [date, statuses] of Object.entries(attendantAttendanceOverrides)) {
    const existing = attendantAttendance[date] || {};
    for (const [name, value] of Object.entries(statuses)) {
      if (value === null || value === undefined) delete existing[name];
      else existing[name] = value;
    }
    attendantAttendance[date] = existing;
  }

  const balances = billing.calculateBalances({
    patient,
    stays: staysList,
    pricing,
    attendance,
    attendantAttendance,
    nowMs: now,
  });
  const current = balances.find((b) => b.id === billing.currentCycle(patient));

  const start = billing.dayStartMs(
    billing.toMs(
      patient.registrationDate !== null && patient.registrationDate !== undefined
        ? patient.registrationDate
        : patient.admissionDate,
      now,
    ),
  );
  const end = billing.dayStartMs(
    billing.toMs(
      patient.exitDate !== null && patient.exitDate !== undefined
        ? patient.exitDate
        : patient.dischargeDate !== null && patient.dischargeDate !== undefined
          ? patient.dischargeDate
          : now,
      now,
    ),
  );
  const cycleAttendance = Object.entries(attendance).filter(([key]) => {
    const dayStart = billing.dayStartMs(new Date(`${key}T00:00:00Z`).getTime());
    return dayStart >= start && dayStart <= end;
  });

  const updates = {
    [`patients/${patientId}/advanceBilledAmount`]: current.total,
    [`patients/${patientId}/attendanceCharges`]: 0,
    [`patients/${patientId}/totalPaidAmount`]: current.netPaid,
    [`patients/${patientId}/currentDueAmount`]: current.due,
    [`patients/${patientId}/refundDueAmount`]: current.refundDue,
    [`patients/${patientId}/totalRefundDueAmount`]: balances.reduce(
      (sum, b) => sum + b.refundDue,
      0,
    ),
    [`patients/${patientId}/totalRefundedAmount`]: balances.reduce(
      (sum, b) => sum + b.refunded,
      0,
    ),
    [`patients/${patientId}/paymentPending`]: current.due > 0,
    [`patients/${patientId}/paymentStatus`]: current.status,
    [`patients/${patientId}/admissionBalances`]: Object.fromEntries(
      balances.map((b) => [b.id, b.toMap()]),
    ),
    [`patients/${patientId}/totalPresentDays`]: cycleAttendance.filter(
      ([, status]) => status === 'Present',
    ).length,
    [`patients/${patientId}/totalAbsentDays`]: cycleAttendance.filter(
      ([, status]) => status === 'Absent',
    ).length,
    [`patients/${patientId}/updatedAt`]: now,
  };
  if (staysList.length > 0) {
    updates[`patients/${patientId}/billingAmountOverride`] = null;
  }
  for (const stayId of migratedDynamicRateIds) {
    updates[`stays/${stayId}/dailyRate`] = null;
  }
  if (migrateGeneralRate) {
    updates['admin_settings/pricing/generalRoomBedPrice'] = 200;
  }

  for (const balance of balances) {
    for (const stay of balance.stays) {
      const snapshotEmpty =
        !stay.patientSnapshot ||
        Object.keys(stay.patientSnapshot).length === 0;
      if (snapshotEmpty && balance.id === billing.currentCycle(patient)) {
        updates[`stays/${stay.id}/patientSnapshot`] = {
          registrationNumber: patient.registrationNumber,
          photoRef: patient.photoRef,
          attendants: Array.isArray(patient.attendants)
            ? patient.attendants.map((a) => {
              if (!a || typeof a !== 'object') return a;
              const { photoDataUrl, ...metadata } = a;
              return metadata;
            })
            : patient.attendants,
          admissionDate: billing.toMs(patient.admissionDate, 0),
        };
      }
      updates[`stays/${stay.id}/cycleId`] = balance.id;
      updates[`stays/${stay.id}/totalCost`] = balance.charges[stay.id];
      updates[`stays/${stay.id}/billableDays`] = balance.days[stay.id];
      updates[`stays/${stay.id}/billingSummary`] = balance.toMap();
      if (stay.status !== 'active') {
        updates[`stays/${stay.id}/completedAt`] = billing.toMs(
          stay.completedAt !== null && stay.completedAt !== undefined
            ? stay.completedAt
            : stay.updatedAt,
          now,
        );
      }
    }
  }
  return {
    updates,
    balances,
    current,
    patient,
    staysList,
    pricing,
    attendance,
    attendantAttendance,
  };
}

module.exports = { loadStays, buildBillingUpdates };
