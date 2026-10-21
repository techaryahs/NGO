import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ngo/models/stay_model.dart';
import 'package:ngo/screens/rooms/widgets/extend_stay_dialog.dart';
import 'package:ngo/services/backend_api_service.dart';
import 'package:ngo/services/service_locator.dart';

void main() {
  late BackendApiService api;
  final stay = StayModel.fromMap('quote-stay', {
    'patientId': 'synthetic',
    'patientName': 'Synthetic',
    'roomId': 'room',
    'roomNumber': '1',
    'roomType': 'general',
    'status': 'active',
    'admissionDate': DateTime(2027).millisecondsSinceEpoch,
    'expectedDischargeDate': DateTime(2027, 3, 2).millisecondsSinceEpoch,
    'durationDays': 60,
  });
  void configure(Future<http.Response> Function(http.Request) handler) {
    api = BackendApiService(
      baseUrl: 'http://localhost/api',
      client: MockClient(handler),
    );
    ServiceLocator().roomService = RoomService(backendApiService: api);
  }

  Widget dialog() => MaterialApp(
    home: Scaffold(body: ExtendStayDialog(stay: stay)),
  );
  ElevatedButton approval(WidgetTester tester) => tester.widget<ElevatedButton>(
    find.byWidgetPredicate((widget) => widget is ElevatedButton),
  );
  tearDown(() {
    api.dispose();
    ServiceLocator().dispose();
  });

  testWidgets('approval waits for the server attendance quote', (tester) async {
    final response = Completer<http.Response>();
    configure((request) {
      expect(request.url.path, '/api/stays/extension-quote');
      expect(request.url.queryParameters, {
        'stayId': 'quote-stay',
        'additionalDays': '7',
      });
      return response.future;
    });
    await tester.pumpWidget(dialog());
    expect(approval(tester).onPressed, isNull);
    response.complete(http.Response(jsonEncode({'additionalCost': 1750}), 200));
    await tester.pumpAndSettle();
    expect(find.text('₹1750.00'), findsOneWidget);
    expect(approval(tester).onPressed, isNotNull);
  });

  testWidgets('a failed quote keeps approval disabled', (tester) async {
    configure((_) async => http.Response('Unauthorized', 401));
    await tester.pumpWidget(dialog());
    await tester.pumpAndSettle();
    expect(approval(tester).onPressed, isNull);
    expect(
      find.textContaining('Could not load the attendance-based quote'),
      findsOneWidget,
    );
    expect(find.text('₹0.00'), findsNothing);
  });

  testWidgets('an older quote cannot overwrite a changed day selection', (
    tester,
  ) async {
    final old = Completer<http.Response>();
    final latest = Completer<http.Response>();
    configure(
      (request) => request.url.queryParameters['additionalDays'] == '7'
          ? old.future
          : latest.future,
    );
    await tester.pumpWidget(dialog());
    await tester.tap(find.byIcon(Icons.add_circle_outline_rounded).last);
    await tester.pump();
    latest.complete(http.Response(jsonEncode({'additionalCost': 2000}), 200));
    await tester.pumpAndSettle();
    old.complete(http.Response(jsonEncode({'additionalCost': 1750}), 200));
    await tester.pumpAndSettle();
    expect(find.text('₹2000.00'), findsOneWidget);
    expect(find.text('₹1750.00'), findsNothing);
  });
}
