import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ngo/models/room_model.dart';
import 'package:ngo/screens/patients/widgets/add_patient_dialog.dart';
import 'package:ngo/services/firebase_rtdb_rest_service.dart';
import 'package:ngo/services/room_service.dart';
import 'package:ngo/services/service_locator.dart';

/// Test RTDB service allowing precise control over each endpoint's response.
class ConfigurableRTDBService extends FirebaseRTDBRestService {
  ConfigurableRTDBService() : super(projectId: 'test-project');

  Future<dynamic> Function(String path)? getHandler;
  Stream<dynamic> Function(String path)? streamHandler;
  Stream<dynamic> Function(String path, {String? orderBy, dynamic equalTo})?
      queryStreamHandler;

  @override
  Future<dynamic> get(String path) async {
    if (getHandler != null) {
      return await getHandler!(path);
    }
    return null;
  }

  @override
  Stream<dynamic> stream(String path, {Duration? pollInterval}) {
    if (streamHandler != null) {
      return streamHandler!(path);
    }
    return Stream.value(null);
  }

  @override
  Stream<dynamic> queryStream(
    String path, {
    String? orderBy,
    dynamic equalTo,
    int? limitToFirst,
    int? limitToLast,
    Duration? pollInterval,
  }) {
    if (queryStreamHandler != null) {
      return queryStreamHandler!(path, orderBy: orderBy, equalTo: equalTo);
    }
    return Stream.value(null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ConfigurableRTDBService mockRtdb;
  late RoomService mockRoomService;

  setUp(() {
    mockRtdb = ConfigurableRTDBService();
    mockRoomService = RoomService(rtdbService: mockRtdb);
    ServiceLocator().roomService = mockRoomService;
  });

  tearDown(() {
    ServiceLocator().dispose();
  });

  Widget buildTestDialog() {
    return const MaterialApp(
      home: Scaffold(
        body: AddPatientDialog(),
      ),
    );
  }

  Future<void> selectFloorAndLobby(
    WidgetTester tester, {
    String floor = '1',
    String lobby = '1D Lobby 1',
  }) async {
    // 1. Scroll to floor dropdown (first 'Select floor first' widget)
    final floorDropdown = find.text('Select floor first').first;
    await tester.scrollUntilVisible(
      floorDropdown,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    // 2. Select floor
    await tester.tap(floorDropdown, warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(DropdownMenuItem<String>, floor).last, warnIfMissed: false);
    await tester.pumpAndSettle();

    // 3. Scroll to lobby dropdown
    final lobbyDropdown = find.text('Select lobby placement').first;
    await tester.scrollUntilVisible(
      lobbyDropdown,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    // 4. Select lobby
    await tester.tap(lobbyDropdown, warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(DropdownMenuItem<String>, lobby).last, warnIfMissed: false);
    await tester.pumpAndSettle();

    // 5. Scroll to payment summary
    final paymentSummary = find.text('PAYMENT SUMMARY').first;
    await tester.scrollUntilVisible(
      paymentSummary,
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  group('AddPatientDialog Independent Pricing & Stay Loading Tests', () {
    testWidgets(
      'Scenario 1: Pricing succeeds while active stays fails with HTTP 400 (missing index) -> pricingLoaded == true and displayed',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1400, 1000);
        addTearDown(() => tester.view.resetPhysicalSize());

        // Pricing succeeds with custom rate
        mockRtdb.getHandler = (path) async {
          if (path.contains('pricing')) {
            return {
              'generalRoomBedPrice': 250,
              'privateRoomBasePrice': 800,
              'privateRoomIncludedAttendants': 1,
              'privateRoomExtraAttendantFee': 250,
            };
          }
          return null;
        };

        // Rooms stream succeeds
        mockRtdb.streamHandler = (path) {
          if (path.contains('rooms')) {
            return Stream.value({
              'room-101': {
                'roomNumber': '101',
                'roomIdentifier': '101',
                'roomType': 'general',
                'capacity': 4,
                'floor': 1,
                'basePrice': 200,
                'status': 'available',
                'beds': {
                  'bed-1': {'id': 'room-101_bed1', 'bedLabel': 'Bed 1', 'status': 'available'},
                },
              },
            });
          }
          return Stream.value(null);
        };

        // Stays query fails with missing index (the exact production root cause)
        mockRtdb.queryStreamHandler = (path, {orderBy, equalTo}) {
          return Stream.error(
            Exception('Index not defined, add ".indexOn": "status", for path "/stays"'),
          );
        };

        await tester.pumpWidget(buildTestDialog());
        await tester.pumpAndSettle();

        // Verify the dialog rendered
        expect(find.text('Add patient'), findsOneWidget);

        // Select Floor 1 and Lobby
        await selectFloorAndLobby(tester, floor: '1', lobby: '1D Lobby 1');

        // VERIFY: Pricing resolved! It MUST NOT be stuck on 'Loading current pricing…'
        expect(find.text('Loading current pricing…'), findsNothing);
        expect(find.text('PAYMENT SUMMARY'), findsOneWidget);
        // Calculated total with custom pricing ₹250 * 7 days = ₹1,750
        expect(find.text('₹1,750'), findsOneWidget);
      },
    );

    testWidgets(
      'Scenario 2: Pricing fails -> fallback default pricing used, pricingLoaded == true, Standard Rates indicator shown',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1400, 1000);
        addTearDown(() => tester.view.resetPhysicalSize());

        // Pricing fails with server error
        mockRtdb.getHandler = (path) async {
          if (path.contains('pricing')) {
            throw Exception('RTDB 500 Internal Server Error');
          }
          return null;
        };

        // Rooms succeed
        mockRtdb.streamHandler = (path) {
          return Stream.value({
            'room-101': {
              'roomNumber': '101',
              'roomIdentifier': '101',
              'roomType': 'general',
              'capacity': 4,
              'floor': 1,
              'basePrice': 200,
              'status': 'available',
            },
          });
        };

        mockRtdb.queryStreamHandler = (path, {orderBy, equalTo}) {
          return Stream.value({});
        };

        await tester.pumpWidget(buildTestDialog());
        await tester.pumpAndSettle();

        // Select Floor 1 and Lobby
        await selectFloorAndLobby(tester, floor: '1', lobby: '1D Lobby 1');

        // VERIFY: Pricing resolved using fallback RoomService.defaultPricing!
        expect(find.text('Loading current pricing…'), findsNothing);
        expect(find.text('PAYMENT SUMMARY'), findsOneWidget);
        expect(find.text('Standard Rates'), findsOneWidget);
        // Fallback default pricing: general bed = ₹200 * 7 days = ₹1,400
        expect(find.text('₹1,400'), findsOneWidget);
      },
    );

    testWidgets(
      'Scenario 3: Rooms loading fails -> pricing still loads independently',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1400, 1000);
        addTearDown(() => tester.view.resetPhysicalSize());

        // Pricing succeeds
        mockRtdb.getHandler = (path) async {
          if (path.contains('pricing')) {
            return {
              'generalRoomBedPrice': 300,
              'privateRoomBasePrice': 700,
            };
          }
          return null;
        };

        // Rooms stream fails
        mockRtdb.streamHandler = (path) {
          return Stream.error(Exception('Network error fetching rooms'));
        };

        mockRtdb.queryStreamHandler = (path, {orderBy, equalTo}) {
          return Stream.value({});
        };

        await tester.pumpWidget(buildTestDialog());
        await tester.pumpAndSettle();

        // Select Floor 1 and Lobby
        await selectFloorAndLobby(tester, floor: '1', lobby: '1D Lobby 1');

        // VERIFY: Pricing is loaded despite rooms failure
        expect(find.text('Loading current pricing…'), findsNothing);
        expect(find.text('PAYMENT SUMMARY'), findsOneWidget);
        // ₹300 * 7 days = ₹2,100
        expect(find.text('₹2,100'), findsOneWidget);
      },
    );

    testWidgets(
      'Scenario 4: Active stays query fails -> room selection remains available without infinite loading',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1400, 1000);
        addTearDown(() => tester.view.resetPhysicalSize());

        // Pricing succeeds
        mockRtdb.getHandler = (path) async {
          if (path.contains('pricing')) {
            return RoomService.defaultPricing;
          }
          return null;
        };

        // Rooms succeed
        mockRtdb.streamHandler = (path) {
          return Stream.value({
            'room-101': {
              'roomNumber': '101',
              'roomIdentifier': '101',
              'roomType': 'general',
              'capacity': 4,
              'floor': 1,
              'basePrice': 200,
              'status': 'available',
              'beds': {
                'bed-1': {'id': 'room-101_bed1', 'bedLabel': 'Bed 1', 'status': 'available'},
              },
            },
          });
        };

        // Stays query fails
        mockRtdb.queryStreamHandler = (path, {orderBy, equalTo}) {
          return Stream.error(Exception('Missing index on stays'));
        };

        await tester.pumpWidget(buildTestDialog());
        await tester.pumpAndSettle();

        // Select Floor 1 (first 'Select floor first')
        final floorDropdown = find.text('Select floor first').first;
        await tester.scrollUntilVisible(
          floorDropdown,
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();

        await tester.tap(floorDropdown, warnIfMissed: false);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(DropdownMenuItem<String>, '1').last, warnIfMissed: false);
        await tester.pumpAndSettle();

        // Room dropdown is available with hint "Select room"
        final roomDropdown = find.text('Select room').first;
        await tester.scrollUntilVisible(
          roomDropdown,
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();

        await tester.tap(roomDropdown, warnIfMissed: false);
        await tester.pumpAndSettle();

        // Room 101 item is found and selectable
        expect(find.textContaining('101'), findsWidgets);
      },
    );

    testWidgets(
      'Scenario 5: All requests succeed -> normal production flow',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1400, 1000);
        addTearDown(() => tester.view.resetPhysicalSize());

        mockRtdb.getHandler = (path) async {
          if (path.contains('pricing')) {
            return {
              'generalRoomBedPrice': 200,
              'privateRoomBasePrice': 700,
              'privateRoomIncludedAttendants': 1,
              'privateRoomExtraAttendantFee': 200,
            };
          }
          return null;
        };

        mockRtdb.streamHandler = (path) {
          return Stream.value({
            'room-101': {
              'roomNumber': '101',
              'roomIdentifier': '101',
              'roomType': 'general',
              'capacity': 4,
              'floor': 1,
              'basePrice': 200,
              'status': 'available',
            },
          });
        };

        mockRtdb.queryStreamHandler = (path, {orderBy, equalTo}) {
          return Stream.value({
            'stay-1': {
              'roomType': 'lobby',
              'roomNumber': '1D Lobby 1',
              'status': 'active',
            },
          });
        };

        await tester.pumpWidget(buildTestDialog());
        await tester.pumpAndSettle();

        // Select Floor 1 and Lobby 2 (since Lobby 1 is occupied)
        await selectFloorAndLobby(tester, floor: '1', lobby: '1D Lobby 2');

        // Normal production flow: pricing loaded, no fallback indicator, correct price
        expect(find.text('PAYMENT SUMMARY'), findsOneWidget);
        expect(find.text('Standard Rates'), findsNothing);
        expect(find.text('₹1,400'), findsOneWidget);
      },
    );

    testWidgets(
      'Scenario 6: Timeout occurs on pricing -> bounded failure falls back to default pricing without infinite loading',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1400, 1000);
        addTearDown(() => tester.view.resetPhysicalSize());

        // Pricing hangs longer than the 6-second timeout
        mockRtdb.getHandler = (path) async {
          if (path.contains('pricing')) {
            await Future.delayed(const Duration(seconds: 10));
            return RoomService.defaultPricing;
          }
          return null;
        };

        mockRtdb.streamHandler = (path) => Stream.value({});
        mockRtdb.queryStreamHandler = (path, {orderBy, equalTo}) => Stream.value({});

        await tester.pumpWidget(buildTestDialog());
        await tester.pump();

        // Advance past the 6-second pricing timeout
        await tester.pump(const Duration(seconds: 7));
        await tester.pumpAndSettle();

        // Select Floor 1 & Lobby to check payment summary
        await selectFloorAndLobby(tester, floor: '1', lobby: '1D Lobby 1');

        // VERIFY: Pricing recovered via fallback after timeout! Not stuck!
        expect(find.text('Loading current pricing…'), findsNothing);
        expect(find.text('PAYMENT SUMMARY'), findsOneWidget);
        expect(find.text('Standard Rates'), findsOneWidget);
        expect(find.text('₹1,400'), findsOneWidget);

        // Advance the remaining delayed future so no timer is left pending
        await tester.pump(const Duration(seconds: 5));
      },
    );
  });
}
