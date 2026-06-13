import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/patient_model.dart';
import '../../../services/service_locator.dart';
import 'edit_patient_dialog.dart';

class PatientDetailsDialog extends StatelessWidget {
  final PatientModel patient;
  final VoidCallback? onUpdated;

  const PatientDetailsDialog({
    super.key,
    required this.patient,
    this.onUpdated,
  });

  void _showEditDialog(BuildContext context) {
    Navigator.of(context).pop(); // Close details dialog
    showDialog(
      context: context,
      builder: (context) =>
          EditPatientDialog(patient: patient, onPatientUpdated: onUpdated),
    );
  }

  void _showDischargeConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Discharge Patient'),
        content: Text(
          'Are you sure you want to discharge ${patient.fullName}? This will remove them from their assigned room.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await ServiceLocator().patientService.dischargePatient(
                  patient.id,
                );
                if (context.mounted) {
                  Navigator.pop(context); // Close confirmation
                  Navigator.pop(context); // Close details dialog
                  onUpdated?.call();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Patient discharged successfully'),
                      backgroundColor: Color(0xFF3B6D11),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: ${e.toString()}'),
                      backgroundColor: const Color(0xFFD32F2F),
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
            ),
            child: const Text('Discharge'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isActive =
        patient.status == 'active' || patient.status.toLowerCase() == 'paid';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        width: 700,
        constraints: const BoxConstraints(maxHeight: 650),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.97),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFC0DD97), width: 0.5),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                decoration: const BoxDecoration(
                  color: Color(0xFFF4F9F0),
                  border: Border(
                    bottom: BorderSide(color: Color(0xFFC0DD97), width: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: isActive
                            ? const Color(0xFFEAF3DE)
                            : const Color(0xFFE8E8E8),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isActive
                              ? const Color(0xFF97C459)
                              : const Color(0xFFBDBDBD),
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          _getInitials(patient.fullName),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: isActive
                                ? const Color(0xFF3B6D11)
                                : const Color(0xFF757575),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            patient.fullName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF27500A),
                            ),
                          ),
                          Text(
                            'Patient ID: ${patient.id.substring(0, 8)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF639922),
                            ),
                          ),
                        ],
                      ),
                    ),
                    _StatusBadge(status: patient.status),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                      color: const Color(0xFF639922),
                    ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Personal Information
                      _Section(
                        label: "Personal Information",
                        child: Column(
                          children: [
                            _Row2(
                              _InfoField(
                                label: "Age",
                                value: "${patient.age} years",
                                icon: Icons.cake_outlined,
                              ),
                              _InfoField(
                                label: "Gender",
                                value:
                                    patient.gender[0].toUpperCase() +
                                    patient.gender.substring(1),
                                icon: Icons.person_outline_rounded,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _Row2(
                              _InfoField(
                                label: "Contact Number",
                                value: patient.contactNumber,
                                icon: Icons.phone_outlined,
                              ),
                              _InfoField(
                                label: "Date of Birth",
                                value:
                                    '${patient.dateOfBirth.day}/${patient.dateOfBirth.month}/${patient.dateOfBirth.year}',
                                icon: Icons.calendar_today_outlined,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Medical Information
                      _Section(
                        label: "Medical Information",
                        child: Column(
                          children: [
                            _InfoField(
                              label: "Medical Condition",
                              value: patient.medicalCondition,
                              icon: Icons.medical_services_outlined,
                              fullWidth: true,
                            ),
                            if (patient.allergies != null) ...[
                              const SizedBox(height: 12),
                              _InfoField(
                                label: "Allergies",
                                value: patient.allergies!,
                                icon: Icons.warning_amber_rounded,
                                fullWidth: true,
                              ),
                            ],
                            if (patient.bloodType != null) ...[
                              const SizedBox(height: 12),
                              _InfoField(
                                label: "Blood Type",
                                value: patient.bloodType!,
                                icon: Icons.bloodtype_outlined,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Emergency Contact
                      _Section(
                        label: "Emergency Contact",
                        child: _Row2(
                          _InfoField(
                            label: "Contact Name",
                            value: patient.emergencyContactName,
                            icon: Icons.contact_emergency_outlined,
                          ),
                          _InfoField(
                            label: "Contact Number",
                            value: patient.emergencyContact,
                            icon: Icons.phone_in_talk_outlined,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Room Assignment
                      if (patient.roomNumber != null) ...[
                        _Section(
                          label: "Room Assignment",
                          child: _Row2(
                            _InfoField(
                              label: "Room Number",
                              value: patient.roomNumber!,
                              icon: Icons.meeting_room_outlined,
                            ),
                            _InfoField(
                              label: "Floor",
                              value: "Floor ${patient.floor}",
                              icon: Icons.layers_outlined,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // Admission Details
                      _Section(
                        label: "Admission Details",
                        child: _Row2(
                          _InfoField(
                            label: "Admission Date",
                            value:
                                '${patient.admissionDate.day}/${patient.admissionDate.month}/${patient.admissionDate.year}',
                            icon: Icons.event_outlined,
                          ),
                          _InfoField(
                            label: "Days Admitted",
                            value: DateTime.now()
                                .difference(patient.admissionDate)
                                .inDays
                                .toString(),
                            icon: Icons.access_time_outlined,
                          ),
                        ),
                      ),

                      // Additional Notes
                      if (patient.notes != null &&
                          patient.notes!.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _Section(
                          label: "Additional Notes",
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF4F9F0),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFFC0DD97),
                              ),
                            ),
                            child: Text(
                              patient.notes!,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF27500A),
                                height: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ],

                      // Payment History Section
                      if (patient.payments != null &&
                          patient.payments!.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        _Section(
                          label: "Payment History",
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF3B6D11),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Text(
                                      "TOTAL PAID",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                    Text(
                                      NumberFormat.currency(
                                        symbol: "₹",
                                        decimalDigits: 0,
                                      ).format(
                                        patient.payments!.fold(
                                          0.0,
                                          (sum, p) => sum + p.amount,
                                        ),
                                      ),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              ...patient.payments!.map((payment) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: _PaymentHistoryTile(payment: payment),
                                );
                              }).toList(),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Footer Actions
              if (isActive)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF4F9F0),
                    border: Border(
                      top: BorderSide(color: Color(0xFFC0DD97), width: 0.5),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _showDischargeConfirmation(context),
                        icon: const Icon(Icons.logout_rounded, size: 16),
                        label: const Text('Discharge Patient'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFD32F2F),
                          side: const BorderSide(color: Color(0xFFD32F2F)),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: () => _showEditDialog(context),
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('Edit Details'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3B6D11),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
  }
}

// Status Badge
class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color textColor;
    String label;

    switch (status.toLowerCase()) {
      case 'active':
        bgColor = const Color(0xFFEAF3DE);
        textColor = const Color(0xFF3B6D11);
        label = 'Active';
        break;
      case 'paid':
        bgColor = const Color(0xFFEAF3DE);
        textColor = const Color(0xFF3B6D11);
        label = 'Paid';
        break;
      case 'discharged':
        bgColor = const Color(0xFFE8E8E8);
        textColor = const Color(0xFF757575);
        label = 'Discharged';
        break;
      default:
        bgColor = const Color(0xFFFFF3E0);
        textColor = const Color(0xFFE65100);
        label = status[0].toUpperCase() + status.substring(1);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }
}

// Section
class _Section extends StatelessWidget {
  final String label;
  final Widget child;

  const _Section({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF639922),
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Divider(color: Color(0xFFC0DD97), thickness: 0.5),
            ),
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

// Info Field
class _InfoField extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool fullWidth;

  const _InfoField({
    required this.label,
    required this.value,
    required this.icon,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F9F0),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFC0DD97)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF3B6D11).withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 18, color: const Color(0xFF3B6D11)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF639922),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF27500A),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Row2 helper
class _Row2 extends StatelessWidget {
  final Widget a, b;
  const _Row2(this.a, this.b);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: a),
        const SizedBox(width: 12),
        Expanded(child: b),
      ],
    );
  }
}

class _PaymentHistoryTile extends StatelessWidget {
  final PaymentModel payment;

  const _PaymentHistoryTile({required this.payment});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(symbol: "₹", decimalDigits: 0);
    final dateFmt = DateFormat('dd MMM yyyy');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFC0DD97).withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F9F0),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              payment.method.toLowerCase().contains('online')
                  ? Icons.qr_code_rounded
                  : payment.method.toLowerCase().contains('check')
                  ? Icons.account_balance_rounded
                  : Icons.money_rounded,
              size: 18,
              color: const Color(0xFF3B6D11),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  payment.method.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF639922),
                  ),
                ),
                Text(
                  dateFmt.format(payment.date),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF27500A),
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                fmt.format(payment.amount),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF3B6D11),
                ),
              ),
              if (payment.receiptNumber != null)
                Text(
                  "Ref: ${payment.receiptNumber}",
                  style: const TextStyle(fontSize: 9, color: Colors.grey),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
