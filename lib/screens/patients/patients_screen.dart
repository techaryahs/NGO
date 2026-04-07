import 'package:flutter/material.dart';
import '../../models/patient_model.dart';
import '../../services/service_locator.dart';
import 'widgets/patient_card.dart';
import 'widgets/add_patient_dialog.dart';
import 'widgets/patient_details_dialog.dart';

class PatientsScreen extends StatefulWidget {
  const PatientsScreen({super.key});

  @override
  State<PatientsScreen> createState() => _PatientsScreenState();
}

class _PatientsScreenState extends State<PatientsScreen> {
  final _searchController = TextEditingController();
  
  String _selectedFilter = 'all'; // 'all', 'active', 'discharged'
  String _searchQuery = '';
  
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showAddPatientDialog() {
    showDialog(
      context: context,
      builder: (context) => AddPatientDialog(
        onPatientAdded: () {
          // Refresh is handled by StreamBuilder
        },
      ),
    );
  }

  void _showPatientDetails(PatientModel patient) {
    showDialog(
      context: context,
      builder: (context) => PatientDetailsDialog(
        patient: patient,
        onUpdated: () {
          // Refresh is handled by StreamBuilder
        },
      ),
    );
  }

  Stream<List<PatientModel>> _getPatientsStream() {
    if (_searchQuery.isNotEmpty) {
      return ServiceLocator().patientService.searchPatients(_searchQuery);
    }
    
    if (_selectedFilter == 'active') {
      return ServiceLocator().patientService.getPatientsByStatus('active');
    } else if (_selectedFilter == 'discharged') {
      return ServiceLocator().patientService.getPatientsByStatus('discharged');
    }
    
    return ServiceLocator().patientService.getPatientsStream();
  }

  List<PatientModel> _filterPatients(List<PatientModel> patients) {
    if (_selectedFilter == 'all') return patients;
    return patients.where((p) => p.status == _selectedFilter).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F7EA),
      body: Column(
        children: [
          // Header with stats
          StreamBuilder<List<PatientModel>>(
            stream: ServiceLocator().patientService.getPatientsStream(),
            builder: (context, snapshot) {
              final allPatients = snapshot.data ?? [];
              final activeCount = allPatients.where((p) => p.status == 'active').length;
              final dischargedCount = allPatients.where((p) => p.status == 'discharged').length;
              final withRoomCount = allPatients.where((p) => p.roomId != null && p.status == 'active').length;

              return Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: Color(0xFFFAFDF7),
                  border: Border(
                    bottom: BorderSide(color: Color(0xFFC0DD97), width: 0.5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Patient Management",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF27500A),
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _showAddPatientDialog,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text("Add Patient"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3B6D11),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _StatCard(
                          label: "Total Patients",
                          value: allPatients.length.toString(),
                          icon: Icons.people_outline_rounded,
                          color: const Color(0xFF3B6D11),
                        ),
                        const SizedBox(width: 12),
                        _StatCard(
                          label: "Active",
                          value: activeCount.toString(),
                          icon: Icons.person_rounded,
                          color: const Color(0xFF639922),
                        ),
                        const SizedBox(width: 12),
                        _StatCard(
                          label: "With Room",
                          value: withRoomCount.toString(),
                          icon: Icons.meeting_room_outlined,
                          color: const Color(0xFF0F6E56),
                        ),
                        const SizedBox(width: 12),
                        _StatCard(
                          label: "Discharged",
                          value: dischargedCount.toString(),
                          icon: Icons.logout_rounded,
                          color: const Color(0xFF757575),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),

          // Search and Filter Bar
          Container(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                // Search Bar
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) {
                      setState(() => _searchQuery = value.toLowerCase());
                    },
                    decoration: InputDecoration(
                      hintText: 'Search patients by name...',
                      hintStyle: TextStyle(
                        color: const Color(0xFF639922).withOpacity(0.5),
                      ),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: Color(0xFF639922),
                      ),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFC0DD97)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFC0DD97)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                          color: Color(0xFF3B6D11),
                          width: 2,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                
                // Filter Chips
                _FilterChip(
                  label: 'All',
                  isSelected: _selectedFilter == 'all',
                  onTap: () => setState(() => _selectedFilter = 'all'),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Active',
                  isSelected: _selectedFilter == 'active',
                  onTap: () => setState(() => _selectedFilter = 'active'),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Discharged',
                  isSelected: _selectedFilter == 'discharged',
                  onTap: () => setState(() => _selectedFilter = 'discharged'),
                ),
              ],
            ),
          ),

          // Patients List
          Expanded(
            child: StreamBuilder<List<PatientModel>>(
              stream: _getPatientsStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF3B6D11),
                    ),
                  );
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          size: 64,
                          color: Color(0xFFD32F2F),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Error: ${snapshot.error}',
                          style: const TextStyle(color: Color(0xFF639922)),
                        ),
                      ],
                    ),
                  );
                }

                final patients = _filterPatients(snapshot.data ?? []);

                if (patients.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.person_outline_rounded,
                          size: 64,
                          color: const Color(0xFF639922).withOpacity(0.3),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.isNotEmpty
                              ? 'No patients found'
                              : 'No patients yet',
                          style: TextStyle(
                            fontSize: 16,
                            color: const Color(0xFF639922).withOpacity(0.6),
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_searchQuery.isEmpty)
                          TextButton.icon(
                            onPressed: _showAddPatientDialog,
                            icon: const Icon(Icons.add_rounded),
                            label: const Text("Add First Patient"),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF3B6D11),
                            ),
                          ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  itemCount: patients.length,
                  itemBuilder: (context, index) {
                    final patient = patients[index];
                    return PatientCard(
                      patient: patient,
                      onTap: () => _showPatientDetails(patient),
                      onEdit: () => _showPatientDetails(patient),
                      onDischarge: () => _showPatientDetails(patient),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// Stat card widget
class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F9F0),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFC0DD97), width: 1),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF639922),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Filter chip widget
class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF3B6D11) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF3B6D11) : const Color(0xFFC0DD97),
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : const Color(0xFF27500A),
          ),
        ),
      ),
    );
  }
}