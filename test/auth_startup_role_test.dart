import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ngo/cache/cache_database.dart';
import 'package:ngo/cache/persistent_cache.dart';
import 'package:ngo/services/auth_service.dart';
import 'package:ngo/services/backend_api_service.dart';
import 'package:ngo/services/firebase_auth_rest_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _RestoredAuth extends FirebaseAuthRestService {
  _RestoredAuth() : super(apiKey: 'synthetic-key');

  final user = AuthUser(uid: 'synthetic-admin', email: 'admin@example.test');

  @override
  AuthUser get currentUser => user;

  @override
  Stream<AuthUser?> get authStateChanges => Stream.value(user);
}

class _PausedActivationCache extends PersistentCache {
  _PausedActivationCache() : super(CacheDatabase(NativeDatabase.memory()));

  final resumeActivation = Completer<void>();

  @override
  Future<void> activateAccount(String accountId) async {
    await resumeActivation.future;
    await super.activateAccount(accountId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _PausedActivationCache cache;
  late _RestoredAuth firebaseAuth;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cache = _PausedActivationCache();
    await cache.initialize();
    firebaseAuth = _RestoredAuth();
    // Let the base service finish its empty, mocked preference restoration.
    await Future<void>.delayed(Duration.zero);
  });

  tearDown(() async {
    if (!cache.resumeActivation.isCompleted) cache.resumeActivation.complete();
    firebaseAuth.dispose();
    await cache.close();
  });

  test('restored admin role waits for cache activation before HTTP', () async {
    var roleRequests = 0;
    final response = Completer<http.Response>();
    final backend = BackendApiService(
      baseUrl: 'https://backend.example/api',
      persistentCache: cache,
      getAuthToken: () async => 'synthetic-token',
      client: MockClient((request) async {
        roleRequests++;
        return response.future;
      }),
    );
    addTearDown(backend.dispose);
    final auth = AuthService(
      authService: firebaseAuth,
      backendApiService: backend,
      persistentCache: cache,
    );

    // Reproduce currentUser starting a lookup before the cache-aware auth
    // stream has finished activation, as happens during desktop restoration.
    final role = auth.getUserRole(firebaseAuth.user.uid);
    final authenticated = auth.authStateChanges.first;
    await Future<void>.delayed(Duration.zero);
    final requestsBeforeActivation = roleRequests;
    cache.resumeActivation.complete();
    expect((await authenticated)?.uid, firebaseAuth.user.uid);
    // Deliver HTTP 200 only after the account generation has changed. A
    // lookup started too early rejects this response as an account switch.
    response.complete(http.Response(jsonEncode({'role': 'admin'}), 200));
    expect(await role, 'admin');
    expect(
      requestsBeforeActivation,
      0,
      reason: 'No profile request before cache activation',
    );
    expect(roleRequests, 1);
  });

  test('role HTTP failure remains an error and a retry can recover', () async {
    cache.resumeActivation.complete();
    await cache.activateAccount(firebaseAuth.user.uid);
    var roleRequests = 0;
    final backend = BackendApiService(
      baseUrl: 'https://backend.example/api',
      persistentCache: cache,
      getAuthToken: () async => 'synthetic-token',
      client: MockClient((request) async {
        roleRequests++;
        return roleRequests == 1
            ? http.Response('{}', 503)
            : http.Response(jsonEncode({'role': 'admin'}), 200);
      }),
    );
    addTearDown(backend.dispose);
    final auth = AuthService(
      authService: firebaseAuth,
      backendApiService: backend,
      persistentCache: cache,
    );

    await expectLater(
      auth.getUserRole(firebaseAuth.user.uid),
      throwsA(isA<BackendApiException>()),
    );
    expect(await auth.getUserRole(firebaseAuth.user.uid), 'admin');
    expect(roleRequests, 2);
  });
}
