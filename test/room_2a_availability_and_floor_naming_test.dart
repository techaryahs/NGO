import 'package:flutter_test/flutter_test.dart';
import 'package:ngo/models/bed_model.dart';
import 'package:ngo/models/room_model.dart';
import 'package:ngo/utils/bed_helper.dart';

void main() {
  group('Room 2A Bed Grouping & Display Name Tests', () {
    test('Room 2A bed labels (bed1, bed2, 1, 2) all map to "Bed 1/2"', () {
      expect(
        BedHelper.getBedDisplayName('bed1', roomIdentifier: '2A'),
        'Bed 1/2',
      );
      expect(
        BedHelper.getBedDisplayName('bed2', roomIdentifier: '2A'),
        'Bed 1/2',
      );
      expect(
        BedHelper.getBedDisplayName('1', roomIdentifier: '2A'),
        'Bed 1/2',
      );
      expect(
        BedHelper.getBedDisplayName('2', roomIdentifier: '2A'),
        'Bed 1/2',
      );
    });

    test('Private rooms 1A and 2B bed labels map correctly without leaking across rooms', () {
      expect(
        BedHelper.getBedDisplayName('bed1', roomIdentifier: '1A'),
        'Bed 1/2',
      );
      expect(
        BedHelper.getBedDisplayName('bed2', roomIdentifier: '1A'),
        'Bed 1/2',
      );
      expect(
        BedHelper.getBedDisplayName('bed1', roomIdentifier: '2B'),
        'Bed 3/4',
      );
      expect(
        BedHelper.getBedDisplayName('bed2', roomIdentifier: '2B'),
        'Bed 3/4',
      );
    });
  });

  group('Room 2A Private Room Single-Occupancy Availability Tests', () {
    final now = DateTime.now();

    RoomModel buildRoom2A({
      required bool bed1Available,
      required bool bed2Available,
      String? bed1PatientId,
      String? bed2PatientId,
    }) {
      return RoomModel(
        id: 'room-2A',
        roomNumber: '2A',
        roomIdentifier: '2A',
        floor: 2,
        roomType: 'private',
        status: (bed1Available && bed2Available) ? 'available' : 'occupied',
        maxAttendants: 5,
        currentAttendants: (bed1Available && bed2Available) ? 0 : 1,
        totalBeds: 2,
        occupiedBeds: (!bed1Available || !bed2Available) ? 1 : 0,
        createdAt: now,
        updatedAt: now,
        beds: [
          BedModel(
            id: 'room-2A_bed1',
            bedLabel: 'bed1',
            status: bed1Available ? 'available' : 'occupied',
            currentPatientId: bed1PatientId,
          ),
          BedModel(
            id: 'room-2A_bed2',
            bedLabel: 'bed2',
            status: bed2Available ? 'available' : 'occupied',
            currentPatientId: bed2PatientId,
          ),
        ],
      );
    }

    test('Vacant private room 2A returns exactly 1 selectable bed unit ("Bed 1/2")', () {
      final room = buildRoom2A(bed1Available: true, bed2Available: true);
      final selectable = BedHelper.selectableAvailableBeds(room);

      expect(selectable.length, 1);
      expect(
        BedHelper.getBedDisplayName(selectable.first.bedLabel, roomIdentifier: '2A'),
        'Bed 1/2',
      );
    });

    test('Partially occupied room 2A (bed 2 occupied by patient) returns 0 selectable beds for new admission', () {
      // Production bug reproducer: bed 2 was occupied, bed 1 was available.
      // Private room single-occupancy must prevent another patient from booking into room 2A.
      final room = buildRoom2A(
        bed1Available: true,
        bed2Available: false,
        bed2PatientId: 'existing-patient-123',
      );
      final selectable = BedHelper.selectableAvailableBeds(room);

      expect(selectable, isEmpty, reason: 'Private room single-occupancy must reject second booking');
    });

    test('Partially occupied room 2A (bed 1 occupied by patient) returns 0 selectable beds for new admission', () {
      final room = buildRoom2A(
        bed1Available: false,
        bed2Available: true,
        bed1PatientId: 'existing-patient-123',
      );
      final selectable = BedHelper.selectableAvailableBeds(room);

      expect(selectable, isEmpty, reason: 'Private room single-occupancy must reject second booking');
    });

    test('Existing patient editing stay in room 2A can retain their bed selection', () {
      final room = buildRoom2A(
        bed1Available: true,
        bed2Available: false,
        bed2PatientId: 'patient-editing-now',
      );
      final selectable = BedHelper.selectableAvailableBeds(
        room,
        selectedBedIds: {'room-2A_bed2'},
      );

      expect(selectable.length, 1);
      expect(selectable.first.id, 'room-2A_bed2');
    });

    test('General ward allows independent bed booking across distinct bed groups', () {
      final generalRoom = RoomModel(
        id: 'room-1B',
        roomNumber: '1B',
        roomIdentifier: '1B',
        floor: 1,
        roomType: 'general',
        status: 'partially_occupied',
        maxAttendants: 5,
        totalBeds: 5,
        createdAt: now,
        updatedAt: now,
        beds: [
          // Group Bed 3/4: bed1 occupied, bed2 available -> group unavailable
          BedModel(
            id: '1B_bed1',
            bedLabel: 'bed1',
            status: 'occupied',
          ),
          BedModel(
            id: '1B_bed2',
            bedLabel: 'bed2',
            status: 'available',
          ),
          // Group Bed 5/6: bed3 available, bed4 available -> group available
          BedModel(
            id: '1B_bed3',
            bedLabel: 'bed3',
            status: 'available',
          ),
          BedModel(
            id: '1B_bed4',
            bedLabel: 'bed4',
            status: 'available',
          ),
          // Group Bed 7: bed5 available -> available
          BedModel(
            id: '1B_bed5',
            bedLabel: 'bed5',
            status: 'available',
          ),
        ],
      );

      final selectable = BedHelper.selectableAvailableBeds(generalRoom);
      // Group Bed 3/4 is occupied (bed1 occupied).
      // Group Bed 5/6 and Group Bed 7 are free.
      expect(selectable.length, 2);
      final labels = selectable.map((b) => BedHelper.getBedDisplayName(b.bedLabel, roomIdentifier: '1B')).toList();
      expect(labels, contains('Bed 5/6'));
      expect(labels, contains('Bed 7'));
      expect(labels.contains('Bed 3/4'), isFalse);
    });
  });
}
