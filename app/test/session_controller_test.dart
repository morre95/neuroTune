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

SessionController controller(AppDatabase database) {
  final config = ExperimentConfig.defaults();
  return SessionController(
    repository: SessionRepository(database),
    api: ApiClient(baseUrl: 'http://localhost:8000'),
    audio: _Audio(),
    keepAlive: _FailingKeepAlive(),
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
}
