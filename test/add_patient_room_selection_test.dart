import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ngo/models/bed_model.dart';
import 'package:ngo/models/room_model.dart';
import 'package:ngo/screens/patients/widgets/add_patient_dialog.dart';
import 'package:ngo/services/firebase_rtdb_rest_service.dart';
import 'package:ngo/services/room_service.dart';
import 'package:ngo/services/service_locator.dart';

/// Configurable mock RTDB service for UI widget tests.
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

  final sampleRooms = {
    'room-1A': {
      'roomNumber': '1A',
      'roomIdentifier': '1A',
      'roomType': 'general',
      'capacity': 4,
      'floor': 1,
      'basePrice': 200,
      'status': 'available',
      'beds': {
        'bed-1': {'id': 'room-1A_bed1', 'bedLabel': 'bed1', 'status': 'available'},
      },
    },
    'room-2A': {
      'roomNumber': '2A',
      'roomIdentifier': '2A',
      'roomType': 'general',
      'capacity': 4,
      'floor': 2,
      'basePrice': 200,
      'status': 'available',
      'beds': {
        'bed-1': {'id': 'room-2A_bed1', 'bedLabel': 'bed1', 'status': 'available'},
      },
    },
  };

  setUp(() {
    mockRtdb = ConfigurableRTDBService();
    mockRoomService = RoomService(rtdbService: mockRtdb);
    ServiceLocator().roomService = mockRoomService;

    // Default: pricing returns immediately
    mockRtdb.getHandler = (path) async {
      if (path.contains('pricing')) {
        return {
          'generalRoomBedPrice': 200,
          'privateRoomBasePrice': 700,
          'lobbyRate': 100,
        };
      }
      return null;
    };

    // Default: rooms stream returns sample rooms
    mockRtdb.streamHandler = (path) {
      if (path.contains('rooms')) {
        return Stream.value(sampleRooms);
      }
      return Stream.value(null);
    };

    // Default: query stream returns empty list of stays
    mockRtdb.queryStreamHandler = (path, {orderBy, equalTo}) {
      return Stream.value({});
    };
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

  group('AddPatient Room Selection & Error Replay Regression Tests', () {
    testWidgets(
      'A. Lobby selected: room dropdown disabled and shows "Clear lobby to select a room"',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1400, 1000);
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(buildTestDialog());
        await tester.pumpAndSettle();

        // 1. Select floor 1
        final floorDropdown = find.text('Select floor first').first;
        await tester.scrollUntilVisible(
          floorDropdown,
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(floorDropdown, warnIfMissed: false);
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(DropdownMenuItem<String>, '1').last,
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();

        // Room dropdown should now show "Select room" before lobby is selected
        expect(find.text('Select room'), findsOneWidget);

        // 2. Select lobby '1D Lobby 1'
        final lobbyDropdown = find.text('Select lobby placement').first;
        await tester.tap(lobbyDropdown, warnIfMissed: false);
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(DropdownMenuItem<String>, '1D Lobby 1').last,
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();

        // VERIFY: Room dropdown now displays "Clear lobby to select a room"
        expect(find.text('Clear lobby to select a room'), findsOneWidget);

        // VERIFY: Room dropdown is disabled (onChanged is null)
        final roomDropdownFinder = find.byType(DropdownButtonFormField<RoomModel>);
        expect(roomDropdownFinder, findsOneWidget);
        final DropdownButtonFormField<RoomModel> roomWidget =
            tester.widget(roomDropdownFinder);
        expect(roomWidget.onChanged, isNull);
      },
    );

    testWidgets(
      'B. Lobby cleared: room dropdown becomes enabled and displays "Select room"',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1400, 1000);
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(buildTestDialog());
        await tester.pumpAndSettle();

        // 1. Select floor 1
        final floorDropdown = find.text('Select floor first').first;
        await tester.scrollUntilVisible(
          floorDropdown,
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(floorDropdown, warnIfMissed: false);
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(DropdownMenuItem<String>, '1').last,
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();

        // 2. Select lobby '1D Lobby 1'
        final lobbyDropdown = find.text('Select lobby placement').first;
        await tester.tap(lobbyDropdown, warnIfMissed: false);
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(DropdownMenuItem<String>, '1D Lobby 1').last,
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();
        expect(find.text('Clear lobby to select a room'), findsOneWidget);

        // 3. Clear lobby using the (X) clear button
        final clearLobbyButton = find.byTooltip('Clear lobby selection');
        expect(clearLobbyButton, findsOneWidget);
        await tester.tap(clearLobbyButton);
        await tester.pumpAndSettle();

        // VERIFY: Room dropdown is now re-enabled
        final roomDropdownFinder = find.byType(DropdownButtonFormField<RoomModel>);
        final DropdownButtonFormField<RoomModel> roomWidget =
            tester.widget(roomDropdownFinder);
        expect(roomWidget.onChanged, isNotNull);

        // VERIFY: Room hint changed back to "Select room"
        expect(find.text('Select room'), findsOneWidget);
        expect(find.text('Clear lobby to select a room'), findsNothing);
      },
    );

    testWidgets(
      'C. Active-stays request fails: room list still loads without hanging',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1400, 1000);
        addTearDown(() => tester.view.resetPhysicalSize());

        // Stays query fails with missing index (production error condition)
        mockRtdb.queryStreamHandler = (path, {orderBy, equalTo}) {
          return Stream.error(
            Exception('Index not defined, add ".indexOn": "status", for path "/stays"'),
          );
        };

        await tester.pumpWidget(buildTestDialog());
        await tester.pumpAndSettle();

        // 1. Select floor 1
        final floorDropdown = find.text('Select floor first').first;
        await tester.scrollUntilVisible(
          floorDropdown,
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(floorDropdown, warnIfMissed: false);
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(DropdownMenuItem<String>, '1').last,
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();

        // VERIFY: Room dropdown is active and shows "Select room"
        final roomDropdown = find.text('Select room').first;
        await tester.scrollUntilVisible(
          roomDropdown,
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('Select room'), findsOneWidget);

        // VERIFY: Tapping room dropdown displays Room 1A despite stays query failure
        await tester.tap(roomDropdown, warnIfMissed: false);
        await tester.pumpAndSettle();

        expect(find.textContaining('1A (Floor Ground - General)'), findsWidgets);
      },
    );

    test(
      'D. Active-stays shared resource is suspended: new subscriber receives the stored error immediately',
      () async {
        // Set up real FirebaseRTDBRestService with MockClient simulating RTDB 400 Bad Request
        final mockClient = MockClient((request) async {
          if (request.url.path.contains('stays')) {
            return http.Response(
              '{"error": "Index not defined, add \\".indexOn\\": \\"status\\", for path \\"/stays\\", to the rules"}',
              400,
            );
          }
          return http.Response('{}', 200);
        });

        final rtdb = FirebaseRTDBRestService(
          projectId: 'test-project',
          httpClient: mockClient,
        );

        final stream = rtdb.queryStream(
          '/stays',
          orderBy: 'status',
          equalTo: 'active',
          pollInterval: const Duration(seconds: 1),
        );

        // First subscriber triggers fetch and encounters 400 error
        dynamic initialError;
        try {
          await stream.first;
        } catch (e) {
          initialError = e;
        }

        expect(initialError, isNotNull);
        expect(initialError.toString(), contains('Index not defined'));

        // Resource is now suspended
        // A SECOND, LATER subscriber must receive the stored error IMMEDIATELY
        // without waiting for any timeout.
        final stopwatch = Stopwatch()..start();
        dynamic lateError;
        try {
          await stream.first.timeout(const Duration(milliseconds: 200));
        } catch (e) {
          lateError = e;
        }
        stopwatch.stop();

        expect(lateError, isNotNull);
        expect(lateError.toString(), contains('Index not defined'));
        // Must complete in under 100ms (replayed immediately, no 8-second hang)
        expect(stopwatch.elapsedMilliseconds, lessThan(100));

        rtdb.dispose();
      },
    );

    testWidgets(
      'E. Room data successfully loads: floor filtering and room selection still work',
      (WidgetTester tester) async {
        tester.view.physicalSize = const Size(1400, 1000);
        addTearDown(() => tester.view.resetPhysicalSize());

        await tester.pumpWidget(buildTestDialog());
        await tester.pumpAndSettle();

        // 1. Select Floor 2
        final floorDropdown = find.text('Select floor first').first;
        await tester.scrollUntilVisible(
          floorDropdown,
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(floorDropdown, warnIfMissed: false);
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(DropdownMenuItem<String>, '2').last,
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();

        // 2. Open room dropdown
        final roomDropdown = find.text('Select room').first;
        await tester.scrollUntilVisible(
          roomDropdown,
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(roomDropdown, warnIfMissed: false);
        await tester.pumpAndSettle();

        // VERIFY: Floor 2 room (2A) is visible, Floor 1 room (1A) is NOT
        expect(find.textContaining('2A (Floor First - General)'), findsWidgets);
        expect(find.textContaining('1A (Floor Ground - General)'), findsNothing);

        // 3. Select Room 2A
        await tester.tap(
          find.textContaining('2A (Floor First - General)').last,
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();

        // VERIFY: Bed selection for Room 2A is visible
        expect(find.text('BED'), findsOneWidget);
        expect(find.text('Bed 1/2'), findsOneWidget);

        // 4. Select Bed 1/2
        await tester.tap(find.text('Bed 1/2'), warnIfMissed: false);
        await tester.pumpAndSettle();

        // VERIFY: Lobby dropdown now displays "Clear room to select a lobby"
        expect(find.text('Clear room to select a lobby'), findsOneWidget);
      },
    );
  });
}
