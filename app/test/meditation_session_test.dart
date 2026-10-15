import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart' hide Uint8List;
import 'package:neurotune/data/database.dart';
import 'package:neurotune/data/repository.dart';
import 'package:neurotune/platform/channels.dart';
import 'package:neurotune/session/session_controller.dart';
import 'package:neurotune_core/neurotune_core.dart';
import 'profile_library_test.dart' show wave, metadata;

class PlaybackAudio implements PcmOutput, PcmPlaybackProgress {
  int accepted = 0;
  int played = 0;
  bool playing = false;
  bool holdTail = false;
  int largestPacket = 0;
  @override
  Future<double?> start(int rate) async {
    accepted = played = 0;
    playing = true;
    return 0;
  }

  @override
  Future<void> write(Uint8List bytes) async {
    largestPacket = bytes.length > largestPacket ? bytes.length : largestPacket;
    accepted += bytes.length ~/ 4;
    // A deterministic virtual device consumes sound immediately except its
    // final queued tail. Production still uses the unshortened 600-second goal.
    played = holdTail && accepted >= 600 * 48000 ? accepted - 4800 : accepted;
  }

  @override
  Future<int> playedFrames() async => played;
  @override
  Future<void> stop() async {
    playing = false;
  }
}

// Recorded-source correlation needs consumption tied to the observed clock;
// the accelerated ten-minute fake above intentionally consumes on acceptance.
class ClockedPlaybackAudio extends PlaybackAudio {
  @override
  Future<void> write(Uint8List bytes) async {
    accepted += bytes.length ~/ 4;
  }
}

class KeepAlive implements SessionKeepAlive {
  bool active = false;
  @override
  Future<void> start() async {
    active = true;
  }

  @override
  Future<void> stop() async {
    active = false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'ten active minutes require the played tail and survive without EEG or optics',
    () async {
      final dir = await Directory.systemTemp.createTemp('meditation-session');
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      addTearDown(() => dir.delete(recursive: true));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => dir.path,
          );
      final bytes = wave();
      final file = await File('${dir.path}/ready.wav').writeAsBytes(bytes);
      final profile = AudioProfileVersion.fromJson(metadata(bytes));
      final audio = PlaybackAudio()..holdTail = true;
      final keepAlive = KeepAlive();
      final config = ExperimentConfig.defaults();
      final session = SessionController(
        repository: SessionRepository(db),
        ownerEmail: 'owner@test',
        audio: audio,
        keepAlive: keepAlive,
        config: config,
        snapshot: BanditSnapshot.empty(
          experimentVersion: config.version,
          origin: DataOrigin.muse,
        ),
        mode: SessionMode.comparison,
        eyeState: EyeState.closed,
        origin: DataOrigin.muse,
        meditation: MeditationSetup(
          profile: profile,
          file: file,
          action: StimulusAction.binaural8,
        ),
      );
      addTearDown(session.dispose);
      expect(await session.start(muse: SilentMuse()), true);
      expect(session.engine!.phase, SessionPhase.sound);
      // Public pump seam follows the fake device's progress without wall time.
      while (audio.accepted < 600 * 48000) {
        await session.pumpPlayback();
      }
      await session.pumpPlayback();
      expect(session.saved, false);
      expect(session.engine!.terminal, false);
      expect(session.view.activeSeconds, 599.9);
      audio.played = audio.accepted;
      await session.pumpPlayback();
      await session.finish();
      final saved = (await session.repository.listSessions()).single;
      expect(saved.status, 'completed');
      expect(saved.manifest.durationSeconds, 600);
      expect(saved.manifest.meditation!['fixed_action'], 'binaural_8');
      expect(saved.manifest.eyeState, 'closed');
      expect(saved.frames, isEmpty);
      expect(audio.playing, false);
      expect(keepAlive.active, false);
      expect(audio.largestPacket, lessThanOrEqualTo(9600 * 4));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
  test(
    'EEG alone retains raw clocks and historical playback eligibility across a pause',
    () async {
      final dir = await Directory.systemTemp.createTemp('meditation-eeg');
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      addTearDown(() => dir.delete(recursive: true));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => dir.path,
          );
      final bytes = wave();
      final file = await File('${dir.path}/ready.wav').writeAsBytes(bytes);
      final profile = AudioProfileVersion.fromJson(metadata(bytes));
      final audio = ClockedPlaybackAudio();
      final muse = StreamMuse();
      var observed = 0.0;
      var lastObserved = -0.000001;
      double readObserved() {
        // The controller's periodic pump still uses real timers. Each reading
        // must remain monotonic even while our virtual clock is stationary.
        lastObserved = observed > lastObserved
            ? observed
            : lastObserved + 0.000001;
        return lastObserved;
      }

      final config = ExperimentConfig.defaults();
      final session = SessionController(
        repository: SessionRepository(db),
        ownerEmail: 'owner@test',
        audio: audio,
        keepAlive: KeepAlive(),
        config: config,
        snapshot: BanditSnapshot.empty(
          experimentVersion: config.version,
          origin: DataOrigin.muse,
        ),
        mode: SessionMode.comparison,
        eyeState: EyeState.open,
        origin: DataOrigin.muse,
        observedTimeSeconds: readObserved,
        meditation: MeditationSetup(
          profile: profile,
          file: file,
          action: StimulusAction.control,
        ),
      );
      addTearDown(session.dispose);
      addTearDown(muse.close);
      expect(await session.start(muse: muse), true);
      await session.pumpPlayback();
      final source = SimulatorSource(
        config: config,
        sampleRateHz: 256,
        seed: 4,
      );
      var nextBatch = .5;
      for (var step = 1; step <= 40; step++) {
        // Join any automatic read before changing the paired fake clocks.
        await session.pumpPlayback();
        observed = step * .15;
        audio.played = (step * .15 * 48000).round();
        await session.pumpPlayback();
        while (nextBatch <= observed + 1e-9) {
          final batch = source.pull().shifted(300);
          for (final contacts in batch.contact) {
            contacts.fillRange(0, contacts.length, 0);
          }
          muse.eegOut.add(batch);
          await Future<void>.delayed(Duration.zero);
          nextBatch += .5;
        }
      }
      muse.lost.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(session.waitingForUser, false); // EEG loss is observational.
      expect(session.engine!.phase, SessionPhase.sound);
      session.interrupt(StopReason.background);
      observed = 9;
      await session.continueSession();
      await session.pumpPlayback();
      nextBatch = 9.5;
      for (var step = 1; step <= 40; step++) {
        await session.pumpPlayback();
        observed = 9 + step * .15;
        audio.played = (step * .15 * 48000).round();
        await session.pumpPlayback();
        if (step == 30) {
          // Exercise automatic pumps while this fixture's virtual time is idle,
          // as happens when the full suite takes longer than the audio tick.
          await Future<void>.delayed(const Duration(milliseconds: 120));
        }
        while (nextBatch <= observed + 1e-9) {
          muse.eegOut.add(source.pull().shifted(303));
          await Future<void>.delayed(Duration.zero);
          nextBatch += .5;
        }
      }
      for (
        var i = 0;
        i < 100 &&
            (session.engine!.frames.isEmpty ||
                session.engine!.frames.last.timeSeconds < 14);
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(session.engine!.frames, isNotEmpty);
      expect(session.engine!.phase, SessionPhase.sound);
      session.interrupt(StopReason.background);
      await session.finish();
      final saved = (await session.repository.listSessions()).single;
      expect(saved.status, 'stopped');
      expect(saved.manifest.stopReason, 'manual');
      expect(saved.frames.every((f) => f.optics.isEmpty), true);
      expect(saved.frames.first.timeSeconds, 4);
      expect(saved.frames.any((f) => f.channels.any((c) => !c.valid)), true);
      expect(
        saved.frames
            .where((f) => f.timeSeconds >= 9 && f.timeSeconds <= 12)
            .every((f) => f.playbackActive == false),
        true,
      );
      expect(saved.frames.last.playbackActive, true);
      expect(
        saved.frames.last.activeTimeSeconds,
        closeTo(saved.frames.last.timeSeconds - 3, .1),
      );
      expect(
        saved.manifest.meditation!['quality_version'],
        config.qualityVersion,
      );
      final job = (await session.repository.pendingUploads()).single;
      final raw = jsonDecode(await File(job.payloadPath).readAsString()) as Map;
      final batches = raw['eeg'] as List;
      expect(batches.first['time_seconds'], 0);
      expect(batches[12]['time_seconds'], 9);
      expect(saved.manifest.durationSeconds, lessThan(14));
    },
  );
  for (final heldWrite in [false, true]) {
    test(
      heldWrite
          ? 'a blocked meditation write is bounded and saves an audio failure'
          : 'stalled played progress cannot inflate meditation duration',
      () async {
        final dir = await Directory.systemTemp.createTemp('meditation-stall');
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        addTearDown(() => dir.delete(recursive: true));
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              (_) async => dir.path,
            );
        final bytes = wave();
        final file = await File('${dir.path}/ready.wav').writeAsBytes(bytes);
        final profile = AudioProfileVersion.fromJson(metadata(bytes));
        final audio = StalledAudio(heldWrite);
        final service = KeepAlive();
        var observed = 0.0;
        final config = ExperimentConfig.defaults();
        final session = SessionController(
          repository: SessionRepository(db),
          ownerEmail: 'owner@test',
          audio: audio,
          keepAlive: service,
          config: config,
          snapshot: BanditSnapshot.empty(
            experimentVersion: config.version,
            origin: DataOrigin.muse,
          ),
          mode: SessionMode.comparison,
          eyeState: EyeState.open,
          origin: DataOrigin.muse,
          observedTimeSeconds: () => observed,
          meditation: MeditationSetup(
            profile: profile,
            file: file,
            action: StimulusAction.control,
          ),
        );
        addTearDown(session.dispose);
        expect(await session.start(muse: SilentMuse()), true);
        if (!heldWrite) {
          await session.pumpPlayback();
          observed = 3;
          await session.pumpPlayback();
        }
        for (var i = 0; i < 300 && !session.saved; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(session.saved, true);
        final saved = (await session.repository.listSessions()).single;
        expect(saved.status, 'stopped');
        expect(saved.manifest.stopReason, 'audioLost');
        expect(saved.manifest.durationSeconds, 0);
        expect(service.active, false);
        expect(audio.packets, 1);
        expect(audio.playing, false);
      },
    );
  }
}

class SilentMuse extends MuseChannel {
  @override
  Stream<EegBatch> get eeg => const Stream.empty();
  @override
  Stream<OpticsBatch> get optics => const Stream.empty();
  @override
  Stream<void> get disconnected => const Stream.empty();
  @override
  Stream<SessionDiagnostic> get diagnostics => const Stream.empty();
  @override
  Future<void> stop() async {}
}

class StreamMuse extends SilentMuse {
  final eegOut = StreamController<EegBatch>.broadcast();
  final lost = StreamController<void>.broadcast();
  @override
  Stream<EegBatch> get eeg => eegOut.stream;
  @override
  Stream<void> get disconnected => lost.stream;
  Future<void> close() async {
    await eegOut.close();
    await lost.close();
  }
}

class StalledAudio extends PlaybackAudio {
  StalledAudio(this.holdWrite);
  final bool holdWrite;
  int packets = 0;
  Completer<void>? pending;
  @override
  Future<void> write(Uint8List bytes) async {
    packets++;
    if (holdWrite) {
      pending = Completer<void>();
      await pending!.future;
    }
    accepted += bytes.length ~/ 4;
  }

  @override
  Future<void> stop() async {
    pending?.complete();
    pending = null;
    playing = false;
  }
}
