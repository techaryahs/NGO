import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ngo/models/bed_model.dart';
import 'package:ngo/models/room_model.dart';
import 'package:ngo/models/stay_model.dart';
import 'package:ngo/services/backend_api_service.dart';
import 'package:ngo/services/room_service.dart';
import 'package:ngo/utils/bed_helper.dart';

void main() {
  group('Room Occupancy Reconciliation Regression Tests', () {
    final now = DateTime.now();

    test(
      'Room 2A with stale occupied bed and completed stays resolves to available and 0 occupied beds',
      () async {
        // Reproduces production scenario:
        // Room 2A (Private Room, Floor 2) has Bed 1 available and Bed 2 stored as occupied
        // by a completed stay. No active stays exist in the room.
        final rawRoomData = {
          'room_2A': {
            'id': 'room_2A',
            'roomNumber': '2A',
            'roomIdentifier': '2A',
            'floor': 2,
            'roomType': 'private',
            'status': 'partially_occupied',
            'maxAttendants': 5,
            'currentAttendants': 1,
            'totalBeds': 2,
            'occupiedBeds': 1,
            'beds': {
              'room_2A_1': {
                'id': 'room_2A_1',
                'bedLabel': '1',
                'status': 'available',
              },
              'room_2A_2': {
                'id': 'room_2A_2',
                'bedLabel': '2',
                'status': 'occupied',
                'currentStayId': 'stay_completed_123',
                'currentPatientId': 'patient_old_456',
              },
            },
            'createdAt': now.millisecondsSinceEpoch,
            'updatedAt': now.millisecondsSinceEpoch,
          },
        };

        // Backend only returns active stays; the completed stay is not active
        final backend = BackendApiService(
          baseUrl: 'http://localhost:8080/api',
          getAuthToken: () async => 'test-token',
          client: MockClient((request) async {
            if (request.url.path == '/api/rooms') {
              return http.Response(jsonEncode(rawRoomData), 200);
            }
            if (request.url.path == '/api/stays') {
              // Empty active stays for room_2A
              return http.Response(jsonEncode({}), 200);
            }
            if (request.url.path == '/api/rooms/room_2A') {
              return http.Response(jsonEncode(rawRoomData['room_2A']), 200);
            }
            return http.Response('Not Found', 404);
          }),
        );
        addTearDown(backend.dispose);

        final roomService = RoomService(backendApiService: backend);
        final rooms = await roomService.streamRooms().first;

        expect(rooms.length, 1);
        final room2A = rooms.first;

        // 1. Room occupancy status must agree with bed statuses and active stays (available)
        expect(room2A.status, 'available');
        expect(room2A.derivedOccupancyStatus, 'available');
        expect(room2A.actualOccupiedBeds, 0);
        expect(room2A.occupiedBeds, 0);
        expect(room2A.currentAttendants, 0);

        // 2. All beds in Room 2A must be marked available
        expect(room2A.beds.length, 2);
        for (final bed in room2A.beds) {
          expect(bed.isAvailable, isTrue);
          expect(bed.isOccupied, isFalse);
          expect(bed.currentStayId, isNull);
          expect(bed.currentPatientId, isNull);
        }

        // 3. Bed 1/2 in private room 2A must be selectable for new patient admission
        final selectable = BedHelper.selectableAvailableBeds(room2A);
        expect(selectable.length, 1);
        expect(
          BedHelper.getBedDisplayName(selectable.first.bedLabel, roomIdentifier: '2A'),
          'Bed 1/2',
        );
      },
    );

    test(
      'computeStatusMeta returns available when activeStays is empty even if room has stale occupied beds',
      () {
        final roomService = RoomService();
        final staleRoom = RoomModel(
          id: 'room_2A',
          roomNumber: '2A',
          roomIdentifier: '2A',
          floor: 2,
          roomType: 'private',
          status: 'partially_occupied',
          maxAttendants: 5,
          currentAttendants: 1,
          totalBeds: 2,
          occupiedBeds: 1,
          createdAt: now,
          updatedAt: now,
          beds: [
            BedModel(id: '2A_1', bedLabel: '1', status: 'available'),
            BedModel(
              id: '2A_2',
              bedLabel: '2',
              status: 'occupied',
              currentStayId: 'stay_old',
              currentPatientId: 'pat_old',
            ),
          ],
        );

        final meta = roomService.computeStatusMeta(staleRoom, [], now);
        expect(meta.dbStatus, 'available');
        expect(meta.uiStatus, 'Available');
        expect(meta.expectedVacancyDate, isNull);
      },
    );

    test(
      'General ward preserves legitimate active stay while clearing stale occupied bed',
      () async {
        final rawRoomData = {
          'room_1B': {
            'id': 'room_1B',
            'roomNumber': '1B',
            'roomIdentifier': '1B',
            'floor': 1,
            'roomType': 'general',
            'status': 'partially_occupied',
            'maxAttendants': 2,
            'totalBeds': 4,
            'occupiedBeds': 2,
            'beds': {
              '1B_bed1': {
                'id': '1B_bed1',
                'bedLabel': 'bed1',
                'status': 'occupied',
                'currentStayId': 'stay_active_1',
                'currentPatientId': 'patient_active_1',
              },
              '1B_bed2': {
                'id': '1B_bed2',
                'bedLabel': 'bed2',
                'status': 'occupied',
                'currentStayId': 'stay_stale_2',
                'currentPatientId': 'patient_stale_2',
              },
              '1B_bed3': {
                'id': '1B_bed3',
                'bedLabel': 'bed3',
                'status': 'available',
              },
              '1B_bed4': {
                'id': '1B_bed4',
                'bedLabel': 'bed4',
                'status': 'maintenance',
              },
            },
            'createdAt': now.millisecondsSinceEpoch,
            'updatedAt': now.millisecondsSinceEpoch,
          },
        };

        final activeStay = StayModel(
          id: 'stay_active_1',
          patientId: 'patient_active_1',
          patientName: 'Active Patient',
          roomId: 'room_1B',
          roomNumber: '1B',
          roomType: 'general',
          admissionDate: now,
          durationDays: 5,
          expectedDischargeDate: now.add(const Duration(days: 5)),
          expiryDate: now.add(const Duration(days: 5)),
          status: 'active',
          bedId: '1B_bed1',
          bedLabel: 'bed1',
          createdAt: now,
          updatedAt: now,
          createdBy: 'admin',
        );

        final backend = BackendApiService(
          baseUrl: 'http://localhost:8080/api',
          getAuthToken: () async => 'test-token',
          client: MockClient((request) async {
            if (request.url.path == '/api/rooms') {
              return http.Response(jsonEncode(rawRoomData), 200);
            }
            if (request.url.path == '/api/stays') {
              return http.Response(jsonEncode({'stay_active_1': activeStay.toMap()}), 200);
            }
            return http.Response('Not Found', 404);
          }),
        );
        addTearDown(backend.dispose);

        final roomService = RoomService(backendApiService: backend);
        final rooms = await roomService.streamRooms().first;

        expect(rooms.length, 1);
        final room1B = rooms.first;

        // 1. Exactly 1 bed is occupied (the legitimate active stay)
        expect(room1B.actualOccupiedBeds, 1);
        expect(room1B.occupiedBeds, 1);
        expect(room1B.status, 'partially_occupied');

        // 2. Check bed statuses
        final bed1 = room1B.beds.firstWhere((b) => b.id == '1B_bed1');
        final bed2 = room1B.beds.firstWhere((b) => b.id == '1B_bed2');
        final bed3 = room1B.beds.firstWhere((b) => b.id == '1B_bed3');
        final bed4 = room1B.beds.firstWhere((b) => b.id == '1B_bed4');

        expect(bed1.isOccupied, isTrue);
        expect(bed1.currentStayId, 'stay_active_1');

        // Stale bed2 must be cleared to available
        expect(bed2.isAvailable, isTrue);
        expect(bed2.isOccupied, isFalse);
        expect(bed2.currentStayId, isNull);

        expect(bed3.isAvailable, isTrue);
        expect(bed4.isMaintenance, isTrue);
      },
    );
  });
}
