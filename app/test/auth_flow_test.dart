import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neurotune/data/api_client.dart';
import 'package:neurotune/data/auth_store.dart';
import 'package:neurotune/data/database.dart';
import 'package:neurotune/main.dart';
import 'package:neurotune/platform/channels.dart';
import 'package:neurotune_core/neurotune_core.dart';

class _AuthApi extends ApiClient {
  _AuthApi() : super(baseUrl: 'http://unused');

  var attempts = 0;

  @override
  Future<AuthTokens> login(String email, String password) async {
    attempts++;
    if (password == 'wrong-password') throw ApiException(401, 'Invalid');
    return AuthTokens(
      accessToken: 'access-token',
      refreshToken: 'refresh-token',
      email: email,
    );
  }

  @override
  Future<ExperimentConfig> activeExperiment() async =>
      ExperimentConfig.defaults();

  @override
  Future<BanditSnapshot> latestBandit({
    required String origin,
    required String experimentVersion,
  }) async => BanditSnapshot.empty(
    experimentVersion: experimentVersion,
    origin: DataOrigin.simulator,
    epsilon: ExperimentConfig.defaults().epsilon,
  );
}

class _TimeoutAuthApi extends _AuthApi {
  @override
  Future<AuthTokens> login(String email, String password) async {
    if (attempts == 0) {
      attempts++;
      throw TimeoutException('Request timed out');
    }
    return super.login(email, password);
  }
}

/// A server whose certificate the phone rejects.
class _UntrustedApi extends _AuthApi {
  @override
  Future<AuthTokens> login(String email, String password) async =>
      throw const HandshakeException('CERTIFICATE_VERIFY_FAILED');
}

class _RefreshApi extends ApiClient {
  _RefreshApi()
    : super(
        baseUrl: 'http://unused',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/v1/auth/refresh');
          return http.Response(
            jsonEncode({
              'access_token': 'new-access',
              'refresh_token': 'new-refresh',
            }),
            200,
          );
        }),
      );

  @override
  Future<ExperimentConfig> activeExperiment() async {
    await refresh();
    return ExperimentConfig.defaults();
  }

  @override
  Future<BanditSnapshot> latestBandit({
    required String origin,
    required String experimentVersion,
  }) async => BanditSnapshot.empty(
    experimentVersion: experimentVersion,
    origin: DataOrigin.simulator,
  );
}

class _KeepAlive implements SessionKeepAlive {
  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}

class _Audio implements PcmOutput {
  @override
  Future<double?> start(int sampleRate) async => 0;

  @override
  Future<void> write(Uint8List pcm16) async {}

  @override
  Future<void> stop() async {}
}

Widget app(AppDatabase database, ApiClient api) => NeuroTuneApp(
  database: database,
  authStore: AuthStore(),
  api: api,
  audio: _Audio(),
  keepAlive: _KeepAlive(),
  muse: MuseChannel(),
);

/// A saved session whose manifest no longer parses.
Future<void> saveBrokenSession(AppDatabase database) => database
    .into(database.storedSessions)
    .insert(
      StoredSessionsCompanion.insert(
        id: 'broken',
        origin: 'simulator',
        mode: 'personal',
        manifestJson: '{}',
        decisionsJson: '[]',
        framesJson: '[]',
        status: 'completed',
        checksum: 'checksum',
        rawPath: 'broken.bin',
        createdAt: DateTime.utc(2026, 9, 27),
      ),
    );

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  testWidgets('wrong password can be corrected in the app', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    final api = _AuthApi();
    addTearDown(database.close);
    await tester.pumpWidget(app(database, api));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'person@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'wrong-password');
    await tester.tap(find.text('Logga in'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Fel e-post eller lösenord'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );

    await tester.enterText(find.byType(TextField).at(1), 'correct-password');
    await tester.tap(find.text('Logga in'));
    await tester.pumpAndSettle();
    expect(api.attempts, 2);
    expect(find.text('Simulator'), findsOneWidget);
  });

  testWidgets('timed out login shows an error and allows retry', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    final api = _TimeoutAuthApi();
    addTearDown(database.close);
    await tester.pumpWidget(app(database, api));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'person@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'password');
    await tester.tap(find.text('Logga in'));
    await tester.pumpAndSettle();
    expect(find.textContaining('tog för lång tid'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );

    await tester.tap(find.text('Logga in'));
    await tester.pumpAndSettle();
    expect(api.attempts, 2);
    expect(find.text('Simulator'), findsOneWidget);
  });

  testWidgets('a login from the database moves to encrypted storage', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.putKv(
      'auth',
      jsonEncode({
        'access_token': 'stored-access',
        'refresh_token': 'stored-refresh',
        'email': 'person@example.com',
      }),
    );
    await tester.pumpWidget(app(database, _AuthApi()));
    await tester.pumpAndSettle();

    expect(await database.getKv('auth'), isNull);
    expect((await AuthStore().load())!.refreshToken, 'stored-refresh');
    expect(find.text('Simulator'), findsOneWidget);
  });

  testWidgets('rotated refresh token is saved for the next app start', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await AuthStore().save(
      AuthTokens(
        accessToken: 'old-access',
        refreshToken: 'old-refresh',
        email: 'person@example.com',
      ),
    );
    await tester.pumpWidget(app(database, _RefreshApi()));
    await tester.pumpAndSettle();

    final saved = (await AuthStore().load())!;
    expect(saved.accessToken, 'new-access');
    expect(saved.refreshToken, 'new-refresh');
    expect(find.text('Simulator'), findsOneWidget);
  });

  testWidgets('unreadable saved login falls back to the login page', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    FlutterSecureStorage.setMockInitialValues({'auth': '{"access_token": 1}'});
    await tester.pumpWidget(app(database, _AuthApi()));
    await tester.pumpAndSettle();

    expect(find.text('Logga in'), findsOneWidget);
    expect(find.textContaining('kunde inte läsas'), findsOneWidget);
  });

  testWidgets('an unreadable login in the database is removed', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.putKv('auth', '{"access_token": 1}');
    await tester.pumpWidget(app(database, _AuthApi()));
    await tester.pumpAndSettle();

    expect(find.textContaining('kunde inte läsas'), findsOneWidget);
    expect(await database.getKv('auth'), isNull);
  });

  testWidgets('broken local data at start is not blamed on the login', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await saveBrokenSession(database);
    await AuthStore().save(
      AuthTokens(
        accessToken: 'access',
        refreshToken: 'refresh',
        email: 'person@example.com',
      ),
    );
    await tester.pumpWidget(app(database, _AuthApi()));
    await tester.pumpAndSettle();

    expect(find.textContaining('Lokala data'), findsOneWidget);
    expect(find.textContaining('Logga in igen'), findsNothing);
  });

  testWidgets('broken local data at login is not blamed on the server', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await saveBrokenSession(database);
    await tester.pumpWidget(app(database, _AuthApi()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'person@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'password');
    await tester.tap(find.text('Logga in'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Lokala data'), findsOneWidget);
    expect(find.textContaining('Servern nås inte'), findsNothing);
  });

  testWidgets('a rejected certificate is reported as such', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await tester.pumpWidget(app(database, _UntrustedApi()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'person@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'password');
    await tester.tap(find.text('Logga in'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Säker anslutning'), findsOneWidget);
    expect(find.textContaining('svarade inte som väntat'), findsNothing);
  });
}
