import 'dart:async';
import 'dart:convert';
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
  var playing = false;

  @override
  Future<double?> start(int sampleRate) async {
    playing = true;
    return 0;
  }

  var bytesWritten = 0;

  @override
  Future<void> write(Uint8List pcm16) async => bytesWritten += pcm16.length;

  @override
  Future<void> stop() async => playing = false;
}

/// Holds the next start open, as a slow platform channel does. A held start
/// opens the output after any stop sent meanwhile and reports no latency, as
/// the Android bridge does once its track is gone.
class _HeldStartAudio extends _Audio {
  Completer<void>? holdStart;
  final started = Completer<void>();

  @override
  Future<double?> start(int sampleRate) async {
    final hold = holdStart;
    if (hold == null) return super.start(sampleRate);
    if (!started.isCompleted) started.complete();
    await hold.future;
    playing = true;
    return null;
  }
}

/// Holds each write until the output has room, as a full AudioTrack does.
class _SlowAudio extends _Audio {
  final packets = <int>[];
  Completer<void>? pending;

  @override
  Future<void> write(Uint8List pcm16) {
    if (pending != null) throw StateError('concurrent audio writes');
    packets.add(pcm16.length);
    pending = Completer<void>();
    return pending!.future;
  }

  void accept() {
    final write = pending!;
    pending = null;
    write.complete();
  }

  void fail() {
    final write = pending!;
    pending = null;
    write.completeError(StateError('audio device failed'));
  }

  @override
  Future<void> stop() async {
    if (pending != null) accept();
    await super.stop();
  }
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
  final diagnosticOut = StreamController<SessionDiagnostic>.broadcast();

  @override
  Stream<SessionDiagnostic> get diagnostics => diagnosticOut.stream;
  var starts = 0;

  @override
  Stream<EegBatch> get eeg => eegOut.stream;

  @override
  Stream<OpticsBatch> get optics => opticsOut.stream;

  @override
  Stream<void> get disconnected => lost.stream;

  @override
  Future<void> start() async {
    starts += 1;
    await reconnecting?.future;
  }

  /// Holds [start] open, as a slow Bluetooth reconnect does.
  Completer<void>? reconnecting;

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
  PcmOutput? audio,
}) {
  final protocol = config ?? ExperimentConfig.defaults();
  return SessionController(
    repository: SessionRepository(database),
    ownerEmail: 'person@example.com',
    audio: audio ?? _Audio(),
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
  _Muse muse, {
  PcmOutput? audio,
}) async {
  final session = controller(
    database,
    keepAlive: _KeepAlive(),
    config: shortProtocol,
    origin: DataOrigin.muse,
    audio: audio,
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

  test(
    'Muse diagnostics and all optical channels survive save and reload',
    () async {
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
      muse.diagnosticOut.add(
        const SessionDiagnostic(
          timeSeconds: 300,
          type: 'battery',
          values: {'percent': 70.0},
        ),
      );
      muse.diagnosticOut.add(
        const SessionDiagnostic(
          timeSeconds: 301,
          type: 'artifact',
          values: {'blink': true, 'jaw_clench': true, 'headband_on': true},
        ),
      );
      muse.stream(source, 12, 300);
      await until(() => session.engine?.phase == SessionPhase.sound);
      for (var index = 0; index < 10; index++) {
        final batch = source.pull().shifted(300.25);
        if (index == 0) batch.eeg[0][3] = double.nan;
        muse.eegOut.add(batch);
        final optical = source.lastOptics!.shifted(300.25);
        muse.opticsOut.add(
          OpticsBatch(
            channelNames: [for (var i = 1; i <= 8; i++) 'OPTICS$i'],
            unit: optical.unit,
            sampleRateHz: optical.sampleRateHz,
            timeSeconds: optical.timeSeconds,
            values: [
              for (var i = 0; i < 8; i++)
                List<double>.of(optical.values[i % 2]),
            ],
          ),
        );
      }
      await until(() => session.engine!.frames.last.timeSeconds >= 16);
      await session.finish();
      final saved = (await session.repository.listSessions()).single;
      expect(saved.manifest.diagnosticsVersion, 1);
      expect(
        saved.manifest.diagnostics
            .where((e) => e.type == 'battery')
            .single
            .values['percent'],
        70,
      );
      expect(
        saved.manifest.diagnostics
            .where((e) => e.type == 'artifact')
            .single
            .values['blink'],
        isTrue,
      );
      expect(
        saved.manifest.diagnostics.any(
          (e) => e.type == 'data_gap' && e.values['stream'] == 'eeg',
        ),
        isTrue,
      );
      expect(
        saved.manifest.diagnostics
            .where((e) => e.type == 'invalid_samples')
            .single
            .values['channel_counts'],
        {simulatorChannels.first: 1},
      );
      expect(
        saved.frames.last.optics.map((e) => e.name),
        containsAll([for (var i = 1; i <= 8; i++) 'OPTICS$i']),
      );
      final upload = (await session.repository.pendingUploads()).single;
      final raw =
          jsonDecode(await File(upload.payloadPath).readAsString())
              as Map<String, dynamic>;
      expect(raw['diagnostics'], saved.manifest.toJson()['diagnostics']);
      expect(raw['diagnostics_version'], 1);
      expect((raw['optics'] as List).last['channel_names'], hasLength(8));
      expect(
        (raw['eeg'] as List).any(
          (batch) => (batch['eeg'][0] as List).contains(null),
        ),
        isTrue,
      );
    },
  );

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
    muse.lost.add(null); // Both platform streams can report the same loss.
    await until(() => session.waitingForUser);
    expect(session.engine!.interruptions, 1);
    await session.continueSession();
    // The bridge clock kept running for the five seconds without signal.
    muse.stream(source, 10, 305);

    await until(() => session.engine!.phase == SessionPhase.sound);
    expect(muse.starts, 1);
    expect(session.engine!.frames.last.timeSeconds, greaterThan(20));
    await session.finish();
    final saved = (await session.repository.listSessions()).single;
    expect(
      saved.manifest.diagnostics
          .where((e) => e.type == 'connection')
          .map((e) => e.values['state']),
      ['connected', 'disconnected', 'connected'],
    );
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

  test('finishing during a reconnect leaves the audio stopped', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final muse = _Muse();
    final audio = _Audio();
    final session = await _startMuseSession(database, muse, audio: audio);
    addTearDown(session.dispose);
    muse.stream(
      SimulatorSource(config: shortProtocol, sampleRateHz: 256, seed: 1),
      12,
      300,
    );
    await until(() => session.engine?.phase == SessionPhase.sound);
    muse.lost.add(null);
    await until(() => session.waitingForUser);

    muse.reconnecting = Completer<void>();
    final resuming = session.continueSession();
    final finishing = session.finish();
    muse.reconnecting!.complete();
    await resuming;
    await finishing;

    expect(session.saved, isTrue);
    expect(audio.playing, isFalse);
  });

  test('audio starts written ahead of playback and stops on finish', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final audio = _Audio();
    final session = await _startMuseSession(database, _Muse(), audio: audio);
    addTearDown(session.dispose);
    const bytesPerSecond = 48000 * 4;

    expect(audio.bytesWritten, greaterThanOrEqualTo(0.15 * bytesPerSecond));

    await session.finish();
    final written = audio.bytesWritten;
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(audio.playing, isFalse);
    expect(audio.bytesWritten, written);
  });

  test('slow audio stays bounded and does not replay a long backlog', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final audio = _SlowAudio();
    final session = await _startMuseSession(database, _Muse(), audio: audio);
    addTearDown(session.dispose);

    // Several timer ticks pass while the native buffer cannot accept data.
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(audio.packets, hasLength(1));
    audio.accept();
    await until(() => audio.packets.length == 2);
    // Even after a long stall, each packet is at most 200 ms of stereo PCM.
    expect(audio.packets.every((bytes) => bytes <= 48000 * 4 ~/ 5), isTrue);
    expect(audio.packets.last, 48000 * 4 ~/ 5);

    // Stopping releases the outstanding write and produces no more packets.
    await session.finish();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(audio.pending, isNull);
    expect(audio.packets, hasLength(2));
    expect(audio.playing, isFalse);
  });

  test(
    'audio write failure ends and saves the session without escaping',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final audio = _SlowAudio();
      final session = await _startMuseSession(database, _Muse(), audio: audio);
      addTearDown(session.dispose);

      audio.fail();
      await until(() => session.saved);
      expect(session.engine!.stopReason, StopReason.audioLost);
      expect(session.error, contains('Ljudutgången slutade fungera'));
      expect(audio.playing, isFalse);
      expect(
        (await session.repository.listSessions()).single.manifest.stopReason,
        'audioLost',
      );
    },
  );

  test(
    'a stalled audio write aborts and saves instead of completing',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final audio = _SlowAudio();
      final muse = _Muse();
      final session = await _startMuseSession(database, muse, audio: audio);
      addTearDown(session.dispose);
      final source = SimulatorSource(
        config: shortProtocol,
        sampleRateHz: 256,
        seed: 1,
      );
      // EEG keeps arriving while the platform never acknowledges the first
      // silent packet. The watchdog must abort before any block can complete.
      muse.stream(source, 40, 300);
      await until(() => session.saved);

      expect(session.engine!.phase, SessionPhase.stopped);
      expect(session.engine!.stopReason, StopReason.audioLost);
      expect(session.error, contains('Ljudutgången slutade fungera'));
      expect(audio.packets, hasLength(1));
      expect(audio.pending, isNull);
      expect(audio.playing, isFalse);
      final saved = (await session.repository.listSessions()).single;
      expect(saved.status, 'stopped');
      expect(saved.manifest.stopReason, 'audioLost');
      expect(
        saved.decisions.every((decision) => !decision.updatedBandit),
        isTrue,
      );

      // Late data cannot turn the aborted session into a completed one.
      muse.stream(source, 28, 300);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(session.engine!.phase, SessionPhase.stopped);
      expect(audio.packets, hasLength(1));
    },
  );
  test(
    'frames wait for audio and resume scoring when it accepts data',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final audio = _SlowAudio();
      final muse = _Muse();
      final session = await _startMuseSession(database, muse, audio: audio);
      addTearDown(session.dispose);
      muse.stream(
        SimulatorSource(config: shortProtocol, sampleRateHz: 256, seed: 1),
        12,
        300,
      );
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(session.engine!.frames, isEmpty);
      expect(session.engine!.phase, SessionPhase.baseline);

      await until(() {
        if (audio.pending != null) audio.accept();
        return session.engine!.phase == SessionPhase.sound;
      });
      expect(session.engine!.frames.length, greaterThanOrEqualTo(9));
      expect(session.error, isNull);
      await session.finish();
    },
  );

  test(
    'a disconnect while audio restarts waits for the user instead of aborting',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final muse = _Muse();
      final audio = _HeldStartAudio();
      final session = await _startMuseSession(database, muse, audio: audio);
      addTearDown(session.dispose);
      muse.stream(
        SimulatorSource(config: shortProtocol, sampleRateHz: 256, seed: 1),
        12,
        300,
      );
      await until(() => session.engine?.phase == SessionPhase.sound);
      muse.lost.add(null);
      await until(() => session.waitingForUser);

      audio.holdStart = Completer<void>();
      final resuming = session.continueSession();
      await audio.started.future;
      final interruptions = session.engine!.interruptions;
      muse.lost.add(null);
      await until(() => session.engine!.interruptions > interruptions);
      final written = audio.bytesWritten;
      audio.holdStart!.complete();
      await resuming;
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(session.waitingForUser, isTrue);
      expect(session.engine!.phase, SessionPhase.waitingStable);
      expect(session.engine!.stopReason, isNull);
      expect(session.error, isNull);
      expect(audio.bytesWritten, written);
      expect(audio.playing, isFalse);
      expect(session.latencyMs, 0);
    },
  );
}
