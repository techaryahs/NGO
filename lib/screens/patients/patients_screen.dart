import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import 'add_patient_dialog.dart';

class PatientsScreen extends StatelessWidget {
  const PatientsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: const Center(
        child: Text(
          "Patients List Will Appear Here",
          style: TextStyle(fontSize: 18),
        ),
      ),

      // Floating Add Patient Button
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primaryGreen,
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) => const AddPatientDialog(),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}