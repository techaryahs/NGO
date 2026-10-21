import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ngo/services/backend_api_service.dart';

void main() {
  group('BackendApiService Tests', () {
    test('checkHealth returns true when backend responds with 200', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/health')) {
          return http.Response(json.encode({'status': 'healthy'}), 200);
        }
        return http.Response('Not Found', 404);
      });

      final service = BackendApiService(
        baseUrl: 'http://localhost:8080/api',
        client: mockClient,
      );

      final isHealthy = await service.checkHealth();
      expect(isHealthy, isTrue);
    });

    test('checkReady returns true when database is ready', () async {
      final mockClient = MockClient((request) async {
        if (request.url.path.endsWith('/ready')) {
          return http.Response(
            json.encode({'status': 'ready', 'database': 'connected'}),
            200,
          );
        }
        return http.Response('Service Unavailable', 503);
      });

      final service = BackendApiService(
        baseUrl: 'http://localhost:8080/api',
        client: mockClient,
      );

      final isReady = await service.checkReady();
      expect(isReady, isTrue);
    });

    test(
      'get maps RTDB patients path to /api/patients and injects Bearer token',
      () async {
        late http.Request capturedRequest;

        final mockClient = MockClient((request) async {
          capturedRequest = request;
          return http.Response(
            json.encode({
              'p_1': {'id': 'p_1', 'fullName': 'Test Patient'},
            }),
            200,
          );
        });

        final service = BackendApiService(
          baseUrl: 'http://localhost:8080/api',
          getAuthToken: () async => 'sample_jwt_token',
          client: mockClient,
        );

        final result = await service.get('patients');
        expect(result, isA<Map>());
        expect(result['p_1']['fullName'], equals('Test Patient'));
        expect(
          capturedRequest.headers['authorization'],
          equals('Bearer sample_jwt_token'),
        );
        expect(capturedRequest.url.path, contains('/api/patients'));
      },
    );

    test('push creates record and returns generated id', () async {
      final mockClient = MockClient((request) async {
        return http.Response(json.encode({'id': 'p_999'}), 201);
      });

      final service = BackendApiService(
        baseUrl: 'http://localhost:8080/api',
        client: mockClient,
      );

      final id = await service.push('patients', {'fullName': 'New Patient'});
      expect(id, equals('p_999'));
    });
  });
}
