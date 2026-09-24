import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurotune/data/api_client.dart';
import 'package:neurotune/data/database.dart';
import 'package:neurotune/data/repository.dart';
import 'package:neurotune/platform/channels.dart';
import 'package:neurotune/session/session_controller.dart';
import 'package:neurotune_core/neurotune_core.dart';

class _Audio implements PcmOutput {
  var stopped = false;

  @override
  Future<double?> start(int sampleRate) async => 0;

  @override
  Future<void> write(Uint8List pcm16) async {}

  @override
  Future<void> stop() async => stopped = true;
}

class _FailingKeepAlive implements SessionKeepAlive {
  @override
  Future<void> start() async => throw StateError('foreground service refused');

  @override
  Future<void> stop() async {}
}

class _KeepAlive implements SessionKeepAlive {
  var stopped = false;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async => stopped = true;
}

SessionController controller(
  AppDatabase database, {
  SessionKeepAlive? keepAlive,
}) {
  final config = ExperimentConfig.defaults();
  return SessionController(
    repository: SessionRepository(database),
    api: ApiClient(baseUrl: 'http://localhost:8000'),
    ownerEmail: 'person@example.com',
    audio: _Audio(),
    keepAlive: keepAlive ?? _FailingKeepAlive(),
    config: config,
    snapshot: BanditSnapshot.empty(
      experimentVersion: config.version,
      origin: DataOrigin.simulator,
    ),
    mode: SessionMode.personal,
    eyeState: EyeState.open,
    origin: DataOrigin.simulator,
  );
}

void main() {
  test('start reports a failure instead of throwing', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final session = controller(database);

    expect(await session.start(), isFalse);
    expect(session.error, contains('kunde inte starta'));

    session.dispose();
  });

  test(
    'finish releases the foreground service even when saving fails',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      final keepAlive = _KeepAlive();
      final session = controller(database, keepAlive: keepAlive);
      final config = ExperimentConfig.defaults();
      session.engine = SessionEngine(
        config: config,
        snapshot: BanditSnapshot.empty(
          experimentVersion: config.version,
          origin: DataOrigin.simulator,
        ),
        sessionId: 'unsaveable',
        origin: DataOrigin.simulator,
        mode: SessionMode.personal,
        eyeState: EyeState.open,
        sampleRateHz: 256,
        channelNames: simulatorChannels,
        seed: 1,
        startedAt: DateTime.utc(2026, 9, 24),
      );

      // A closed database makes repository.saveSession throw out of _persist.
      await database.close();
      await expectLater(session.finish(), throwsA(anything));

      expect(keepAlive.stopped, isTrue);
      expect(session.saved, isFalse);

      session.dispose();
    },
  );
}
