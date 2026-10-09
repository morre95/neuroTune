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
import 'package:neurotune/data/repository.dart';
import 'package:neurotune/main.dart';
import 'package:neurotune/platform/channels.dart';
import 'package:neurotune/ui/history_page.dart';
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

class _ConfigPolicyApi extends _AuthApi {
  _ConfigPolicyApi(this.delivered);
  final BanditSnapshot? delivered;

  @override
  Future<ExperimentConfig> activeExperiment() async {
    if (delivered == null) throw const SocketException('Offline');
    return ExperimentConfig.fromJson({
      ...ExperimentConfig.defaults().toJson(),
      'version': '2026.3',
      'quality_version': '2026.3-unverified',
    });
  }

  @override
  Future<BanditSnapshot> latestBandit({
    required String origin,
    required String experimentVersion,
  }) async {
    expect(origin, 'simulator');
    expect(experimentVersion, '2026.4');
    return delivered!;
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

/// Holds the experiment request of a session start open, as a slow network
/// does. The first request, at login, answers at once.
class _SlowStartApi extends _AuthApi {
  var experimentRequests = 0;
  Completer<void>? hold;

  @override
  Future<ExperimentConfig> activeExperiment() async {
    experimentRequests++;
    await hold?.future;
    return super.activeExperiment();
  }
}

class _KeepAlive implements SessionKeepAlive {
  var starts = 0;

  @override
  Future<void> start() async => starts++;

  @override
  Future<void> stop() async {}
}

class _FailingKeepAlive extends _KeepAlive {
  @override
  Future<void> start() async => throw StateError('foreground service refused');
}

class _Audio implements PcmOutput {
  @override
  Future<double?> start(int sampleRate) async => 0;

  @override
  Future<void> write(Uint8List pcm16) async {}

  @override
  Future<void> stop() async {}
}

Widget app(
  AppDatabase database,
  ApiClient api, {
  SessionKeepAlive? keepAlive,
}) => NeuroTuneApp(
  database: database,
  authStore: AuthStore(),
  api: api,
  audio: _Audio(),
  keepAlive: keepAlive ?? _KeepAlive(),
  muse: MuseChannel(),
);

/// A start cancels the contact preview's stream subscription, and that
/// completes on the real event loop, which fake time does not run.
Future<void> letStartRun(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump();
}

/// Logs in and opens the simulator contact page with a signal on it.
Future<void> openSimulatorContact(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 3200);
  addTearDown(tester.view.reset);
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).at(0), 'person@example.com');
  await tester.enterText(find.byType(TextField).at(1), 'password');
  await tester.tap(find.text('Logga in'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Simulator'));
  await tester.pump(const Duration(seconds: 1));
}

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

  for (final scenario in [
    'legacy-cache',
    'current-cache',
    'legacy-http',
    'wrong-origin-http',
  ]) {
    testWidgets(
      'NIR current configuration keeps only compatible source policy: $scenario',
      (tester) async {
        final database = AppDatabase(NativeDatabase.memory());
        addTearDown(database.close);
        final repository = SessionRepository(database);
        final legacy = ExperimentConfig.fromJson({
          ...ExperimentConfig.defaults().toJson(),
          'version': '2026.3',
          'quality_version': '2026.3-unverified',
        });
        await repository.saveConfig(legacy);
        BanditSnapshot policy(
          String version,
          DataOrigin origin,
          String label,
        ) => BanditSnapshot(
          experimentVersion: version,
          dataOrigin: origin.name,
          policyVersion: label,
          epsilon: .2,
          actions: {
            for (final a in StimulusAction.values) a: const ActionStat(12, .5),
          },
          includedSessionIds: const ['historical-reward'],
          createdAtIso: '2026-10-09T00:00:00Z',
        );
        await repository.saveBandit(
          policy(
            scenario == 'current-cache' ? '2026.4' : '2026.3',
            DataOrigin.simulator,
            'cached-policy',
          ),
        );
        await repository.saveBandit(
          policy('2026.4', DataOrigin.muse, 'retained-muse'),
        );
        await AuthStore().save(
          AuthTokens(
            accessToken: 'access',
            refreshToken: 'refresh',
            email: 'person@example.com',
          ),
        );
        final delivered = scenario == 'legacy-http'
            ? policy('2026.3', DataOrigin.simulator, 'wrong-version')
            : scenario == 'wrong-origin-http'
            ? policy('2026.4', DataOrigin.muse, 'wrong-source')
            : null;
        await tester.pumpWidget(app(database, _ConfigPolicyApi(delivered)));
        await tester.pumpAndSettle();
        expect(find.text('Experiment 2026.4'), findsOneWidget);
        expect(
          find.text(
            scenario == 'current-cache' ? 'Policy cached-policy' : 'Policy 0',
          ),
          findsOneWidget,
        );
        expect(
          (await repository.loadBandit('muse'))!.policyVersion,
          'retained-muse',
        );
        // Neither stale cache fallback nor a bad HTTP response relabels or
        // destroys the previous version's cached reward evidence.
        expect(
          (await repository.loadBandit(
            'simulator',
          ))!.actions[StimulusAction.control]!.n,
          12,
        );
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets(
    'default-disabled meditation retains NIR modes and history without library controls',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 3200);
      addTearDown(tester.view.reset);
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await tester.pumpWidget(app(database, _AuthApi()));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).at(0),
        'person@example.com',
      );
      await tester.enterText(find.byType(TextField).at(1), 'password');
      await tester.tap(find.text('Logga in'));
      await tester.pumpAndSettle();

      expect(find.text('Meditation'), findsNothing);
      expect(find.text('Kalibrering'), findsNothing);
      expect(find.text('Ljudprofiler'), findsNothing);
      await tester.tap(find.text('Jämförelse'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Jämförelse mäter utan att träna'),
        findsOneWidget,
      );
      await tester.tap(find.text('Simulator'));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Starta baslinje'), findsOneWidget);
      expect(find.text('Starta meditation'), findsNothing);
      await tester.tap(find.text('Tillbaka'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sessionshistorik'));
      await tester.pumpAndSettle();
      expect(find.byType(HistoryPage), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

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

  testWidgets('a start waiting on the network runs once and can be left', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final api = _SlowStartApi();
    final keepAlive = _KeepAlive();
    await tester.pumpWidget(app(database, api, keepAlive: keepAlive));
    await openSimulatorContact(tester);
    api.hold = Completer<void>();

    // The second tap lands before the page rebuilds with the lock.
    await tester.tap(find.text('Starta baslinje'));
    await tester.tap(find.text('Starta baslinje'));
    await letStartRun(tester);
    expect(find.text('Startar…'), findsOneWidget);
    expect(api.experimentRequests, 2);

    await tester.tap(find.text('Tillbaka'));
    await tester.pump();
    api.hold!.complete();
    await tester.pumpAndSettle();

    expect(find.text('Simulator'), findsOneWidget);
    expect(find.text('Session'), findsNothing);
    expect(keepAlive.starts, 0);
  });

  testWidgets('a failed start shows why and can be retried', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await tester.pumpWidget(
      app(database, _AuthApi(), keepAlive: _FailingKeepAlive()),
    );
    await openSimulatorContact(tester);

    await tester.tap(find.text('Starta baslinje'));
    await letStartRun(tester);
    await tester.pump(const Duration(seconds: 1));

    expect(find.textContaining('kunde inte starta'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Starta baslinje'),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.text('Tillbaka'));
    await tester.pumpAndSettle();
  });
}
