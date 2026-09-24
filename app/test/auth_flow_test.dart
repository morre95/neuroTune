import 'dart:async';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurotune/data/api_client.dart';
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

class _Audio implements PcmOutput {
  @override
  Future<double?> start(int sampleRate) async => 0;

  @override
  Future<void> write(Uint8List pcm16) async {}

  @override
  Future<void> stop() async {}
}

void main() {
  testWidgets('wrong password can be corrected in the app', (tester) async {
    final database = AppDatabase(NativeDatabase.memory());
    final api = _AuthApi();
    addTearDown(database.close);
    await tester.pumpWidget(
      NeuroTuneApp(
        database: database,
        api: api,
        audio: _Audio(),
        muse: MuseChannel(),
      ),
    );
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
    await tester.pumpWidget(
      NeuroTuneApp(
        database: database,
        api: api,
        audio: _Audio(),
        muse: MuseChannel(),
      ),
    );
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
}
