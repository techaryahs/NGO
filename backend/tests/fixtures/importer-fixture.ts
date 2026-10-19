// Entirely synthetic identities and financial values; never derived from records.
export function importerFixture(): Record<string, any> {
  return {
    users: { audit_author: { name: 'Synthetic Import Author', email: 'author@example.test', role: 'volunteer' } },
    system_counters: { registrationNumber: 12 },
    rooms: { audit_room: { roomNumber: 'T-101', roomType: 'general', floor: 1, totalBeds: 1,
      beds: { audit_bed: { bedLabel: 'T-1', status: 'available' } } } },
    patients: { audit_patient: { fullName: 'Synthetic Patient', gender: 'Other', dateOfBirth: '1990-01-01',
      contactNumber: '', emergencyContact: '', emergencyContactName: '', medicalCondition: '',
      admissionDate: '2026-01-01T10:00:00.000Z', roomId: 'audit_room', registrationNumber: 'NGO000012',
      createdBy: 'audit_author', totalPaidAmount: '0.30', currentDueAmount: '9.70',
      attendants: [{ name: 'Synthetic Attendant', relation: 'Family', photoRef: 'synthetic-photo',
        photoDataUrl: 'data:image/png;base64,c3ludGhldGlj' }] } },
    stays: { audit_stay: { patientId: 'audit_patient', roomId: 'audit_room', patientName: 'Synthetic Patient',
      admissionDate: '2026-01-01T10:00:00.000Z', durationDays: 10, bedId: 'audit_bed', totalCost: '10.00' } },
    attendance: { daily: { '2026-01-01': { audit_patient: { isPresent: true } } } },
    attendant_attendance: { daily: { '2026-01-01': { audit_patient: { attendant_0: { isPresent: true } } } } },
    payments: {
      copied_key: { id: 'audit_pay_1', patientId: 'audit_patient', amount: '0.10', date: 1767261600000, method: 'cash' },
      audit_pay_2: { id: 'audit_pay_2', patientId: 'audit_patient', amount: '0.20', date: 1767261600000, method: 'cash' },
    },
    paymentHistory: {
      original_key: { id: 'audit_pay_1', patientId: 'audit_patient', amount: '0.10', date: 1767261600000, method: 'cash' },
    },
    'admin_settings/pricing': { generalRoom: 10 },
  };
}
