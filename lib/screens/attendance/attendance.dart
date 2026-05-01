import 'package:flutter/material.dart';
import '../../services/service_locator.dart';
import '../../models/patient_model.dart';

class Attendance extends StatefulWidget {
  const Attendance({super.key});

  @override
  State<Attendance> createState() => _AttendanceState();
}

class _AttendanceState extends State<Attendance> {
  final Map<String, bool> attendanceStatus = {};

  Future<void> markAttendance(
      String patientId,
      String patientName,
      bool isPresent,
      ) async {
    final today = DateTime.now().toIso8601String().split("T")[0];

    try {
      await ServiceLocator().rtdbService.put(
        "attendance/$today/$patientId",
        {
          "patientId": patientId,
          "patientName": patientName,
          "status": isPresent ? "Present" : "Absent",
          "date": today,
          "timestamp": DateTime.now().toIso8601String(),
        },
      );

      setState(() {
        attendanceStatus[patientId] = isPresent;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: isPresent ? Colors.green : Colors.red,
          content: Text(
            "$patientName marked as ${isPresent ? "Present" : "Absent"}",
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text("Failed to mark attendance: $e"),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F7EA),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Patient Attendance",
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF27500A),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Mark daily attendance for all patients",
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF639922),
              ),
            ),
            const SizedBox(height: 20),

            /// Patient List
            Expanded(
              child: StreamBuilder<List<PatientModel>>(
                stream: ServiceLocator()
                    .patientService
                    .getPatientsStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState ==
                      ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF3B6D11),
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        "Error: ${snapshot.error}",
                      ),
                    );
                  }

                  final patients = snapshot.data ?? [];

                  if (patients.isEmpty) {
                    return const Center(
                      child: Text(
                        "No patients found",
                        style: TextStyle(
                          color: Color(0xFF639922),
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: patients.length,
                    itemBuilder: (context, index) {
                      final patient = patients[index];

                      final patientName =
                          patient.fullName; // use your actual field

                      final status =
                      attendanceStatus[patient.id];

                      return Container(
                        margin:
                        const EdgeInsets.only(bottom: 12),
                        padding:
                        const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius:
                          BorderRadius.circular(14),
                          border: Border.all(
                            color:
                            const Color(0xFFC0DD97),
                          ),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor:
                              const Color(
                                  0xFFEAF3DE),
                              child: Text(
                                patientName.isNotEmpty
                                    ? patientName[0]
                                    .toUpperCase()
                                    : "?",
                                style:
                                const TextStyle(
                                  color: Color(
                                      0xFF27500A),
                                  fontWeight:
                                  FontWeight.bold,
                                ),
                              ),
                            ),

                            const SizedBox(width: 12),

                            /// Patient Info
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                CrossAxisAlignment
                                    .start,
                                children: [
                                  Text(
                                    patientName,
                                    style:
                                    const TextStyle(
                                      fontWeight:
                                      FontWeight
                                          .bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(
                                      height: 4),
                                  Text(
                                    patient.contactNumber ??
                                        "No contact",
                                    style:
                                    const TextStyle(
                                      color: Colors
                                          .grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            /// Present Button
                            ElevatedButton(
                              style:
                              ElevatedButton
                                  .styleFrom(
                                backgroundColor:
                                Colors.green,
                              ),
                              onPressed: () {
                                markAttendance(
                                  patient.id,
                                  patientName,
                                  true,
                                );
                              },
                              child:
                              const Text("Present"),
                            ),

                            const SizedBox(width: 10),

                            /// Absent Button
                            ElevatedButton(
                              style:
                              ElevatedButton
                                  .styleFrom(
                                backgroundColor:
                                Colors.red,
                              ),
                              onPressed: () {
                                markAttendance(
                                  patient.id,
                                  patientName,
                                  false,
                                );
                              },
                              child:
                              const Text("Absent"),
                            ),

                            const SizedBox(width: 12),

                            /// Current Status
                            if (status != null)
                              Container(
                                padding:
                                const EdgeInsets
                                    .symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration:
                                BoxDecoration(
                                  color: status
                                      ? Colors.green
                                      .withOpacity(
                                      0.1)
                                      : Colors.red
                                      .withOpacity(
                                      0.1),
                                  borderRadius:
                                  BorderRadius
                                      .circular(
                                      20),
                                ),
                                child: Text(
                                  status
                                      ? "Present"
                                      : "Absent",
                                  style:
                                  TextStyle(
                                    color: status
                                        ? Colors.green
                                        : Colors.red,
                                    fontWeight:
                                    FontWeight
                                        .bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}