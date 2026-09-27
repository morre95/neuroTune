import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter/services.dart' hide Uint8List;
import 'package:flutter_test/flutter_test.dart';
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

/// A headband whose bridge clock started [bridgeOffset] seconds before the
/// session, as it does after the contact preview.
class _Muse extends MuseChannel {
  final eegOut = StreamController<EegBatch>.broadcast();
  final opticsOut = StreamController<OpticsBatch>.broadcast();
  final lost = StreamController<void>.broadcast();
  var starts = 0;

  @override
  Stream<EegBatch> get eeg => eegOut.stream;

  @override
  Stream<OpticsBatch> get optics => opticsOut.stream;

  @override
  Stream<void> get disconnected => lost.stream;

  @override
  Future<void> start() async => starts += 1;

  @override
  Future<void> stop() async {}

  /// Sends [seconds] of simulated signal stamped on the bridge clock.
  void stream(SimulatorSource source, double seconds, double bridgeOffset) {
    for (var sent = 0.0; sent < seconds; sent += 0.5) {
      eegOut.add(source.pull().shifted(bridgeOffset));
      opticsOut.add(source.lastOptics!.shifted(bridgeOffset));
    }
  }
}

final shortProtocol = ExperimentConfig.defaults().withProtocol(
  baselineSeconds: 10,
  blockCount: 2,
  soundSeconds: 10,
  pauseSeconds: 2,
  rewardTailSeconds: 5,
);

SessionController controller(
  AppDatabase database, {
  SessionKeepAlive? keepAlive,
  ExperimentConfig? config,
  DataOrigin origin = DataOrigin.simulator,
}) {
  final protocol = config ?? ExperimentConfig.defaults();
  return SessionController(
    repository: SessionRepository(database),
    ownerEmail: 'person@example.com',
    audio: _Audio(),
    keepAlive: keepAlive ?? _FailingKeepAlive(),
    config: protocol,
    snapshot: BanditSnapshot.empty(
      experimentVersion: protocol.version,
      origin: origin,
    ),
    mode: SessionMode.personal,
    eyeState: EyeState.open,
    origin: origin,
  );
}

/// Frames come back from the DSP isolate asynchronously.
Future<void> until(bool Function() done) async {
  for (var tries = 0; tries < 500 && !done(); tries++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(done(), isTrue);
}

Future<SessionController> _startMuseSession(
  AppDatabase database,
  _Muse muse,
) async {
  final session = controller(
    database,
    keepAlive: _KeepAlive(),
    config: shortProtocol,
    origin: DataOrigin.muse,
  );
  expect(await session.start(muse: muse), isTrue);
  return session;
}

void documentsAt(String path) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => path,
      );
}

/// Points the documents directory at a file, so creating the sessions folder
/// and therefore saving the session fails.
void failSaving() {
  final folder = Directory.systemTemp.createTempSync('neurotune_test');
  addTearDown(() => folder.deleteSync(recursive: true));
  final blocker = File('${folder.path}/file')..writeAsStringSync('');
  documentsAt(blocker.path);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    final documents = Directory.systemTemp.createTempSync('neurotune_test');
    addTearDown(() => documents.deleteSync(recursive: true));
    documentsAt(documents.path);
  });

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
      addTearDown(database.close);
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

      failSaving();
      await expectLater(session.finish(), throwsA(anything));

      expect(keepAlive.stopped, isTrue);
      expect(session.saved, isFalse);

      session.dispose();
    },
  );

  test('a Muse session starts its timeline at its own first sample', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final muse = _Muse();
    final session = await _startMuseSession(database, muse);
    addTearDown(session.dispose);
    final source = SimulatorSource(
      config: shortProtocol,
      sampleRateHz: 256,
      seed: 1,
    );

    muse.stream(source, 12, 300);
    await until(() => (session.engine?.frames.length ?? 0) >= 9);

    expect(session.engine!.frames.first.timeSeconds, closeTo(4, 1e-9));
    expect(session.engine!.phase, SessionPhase.sound);
  });

  test('a reconnected Muse continues the session timeline', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final muse = _Muse();
    final session = await _startMuseSession(database, muse);
    addTearDown(session.dispose);
    final source = SimulatorSource(
      config: shortProtocol,
      sampleRateHz: 256,
      seed: 1,
    );
    muse.stream(source, 12, 300);
    await until(() => session.engine?.phase == SessionPhase.sound);

    muse.lost.add(null);
    await until(() => session.waitingForUser);
    await session.continueSession();
    // The bridge clock kept running for the five seconds without signal.
    muse.stream(source, 10, 305);

    await until(() => session.engine!.phase == SessionPhase.sound);
    expect(muse.starts, 1);
    expect(session.engine!.frames.last.timeSeconds, greaterThan(20));
  });

  test('a crashed DSP isolate ends and saves the session', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final muse = _Muse();
    final session = await _startMuseSession(database, muse);
    addTearDown(session.dispose);

    // The pipeline throws on a batch at the wrong sample rate.
    muse.eegOut.add(
      SimulatorSource(config: shortProtocol, sampleRateHz: 128, seed: 1).pull(),
    );
    await until(() => session.saved);

    expect(session.engine!.stopReason, StopReason.processingFailed);
    final saved = await SessionRepository(database).listSessions();
    expect(saved.single.manifest.stopReason, 'processingFailed');
  });

  test(
    'a failed automatic save is shown and reaches the finish button',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final muse = _Muse();
      final session = await _startMuseSession(database, muse);
      addTearDown(session.dispose);
      failSaving();

      muse.eegOut.add(
        SimulatorSource(
          config: shortProtocol,
          sampleRateHz: 128,
          seed: 1,
        ).pull(),
      );
      await until(() => session.error?.contains('kunde inte sparas') ?? false);

      expect(session.view.message, contains('kunde inte sparas'));
      await expectLater(session.finish(), throwsA(anything));
      expect(session.saved, isFalse);
    },
  );
}
