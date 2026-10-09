import 'dart:math';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurotune/platform/channels.dart';
import 'package:neurotune_core/neurotune_core.dart';
import 'meditation_interruptions_test.dart' show InterruptedAudio, setup;
import 'meditation_session_test.dart' show SilentMuse;

/// Android streaming output waits for its startup threshold before consuming.
class BufferedAudio extends InterruptedAudio implements PcmStartupThreshold {
  int threshold = 12000; // AudioBridge requests a 250 ms buffer at 48 kHz.
  bool draining = false;
  int largestQueued = 0;
  int consumption = 2400;
  bool underRunFinalTail = false;
  bool finalUnderrunTriggered = false;
  bool recordPackets = true;
  bool holdPadding = false;
  Uint8List? lastPacket;
  final List<int> startHeads = [];
  final List<int> stoppedHeads = [];
  final List<Uint8List> currentPackets = [];

  @override
  Future<int> startupThresholdFrames() async => threshold;

  @override
  Future<double?> start(int rate) async {
    startHeads.add(played);
    currentPackets.clear();
    draining = false;
    return super.start(rate);
  }

  @override
  Future<void> write(Uint8List bytes) async {
    lastPacket = bytes;
    if (recordPackets) currentPackets.add(Uint8List.fromList(bytes));
    accepted += bytes.length ~/ 4;
    largestPacket = max(largestPacket, bytes.length);
    largestQueued = max(largestQueued, accepted - played);
    if (holdPadding && bytes.every((sample) => sample == 0)) {
      pending = Completer<void>();
      await pending!.future;
      pending = null;
    }
  }

  @override
  Future<int> playedFrames() async {
    if (underRunFinalTail &&
        !finalUnderrunTriggered &&
        accepted == MeditationProtocol.totalFrames) {
      finalUnderrunTriggered = true;
      draining = false;
    }
    final queued = accepted - played;
    if (!draining && queued >= threshold) draining = true;
    if (draining) {
      played += min(consumption, queued);
      if (played == accepted) draining = false;
    }
    return played;
  }

  @override
  Future<void> stop() async {
    stoppedHeads.add(played);
    await super.stop();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'meditation primes the native buffer and re-primes a changed sink after resume',
    () async {
      final audio = BufferedAudio();
      final (session, repo, service, _) = await setup(audio);
      expect(await session.start(muse: SilentMuse()), true);
      for (var pump = 0; pump < 10; pump++) {
        await session.pumpPlayback();
      }
      expect(session.activePlaybackFrames, greaterThan(0));
      final beforeRouteChange = session.activePlaybackFrames;
      audio.threshold = 18000;
      audio.draining = false; // Same track under-runs as its route changes.
      for (var pump = 0; pump < 10; pump++) {
        await session.pumpPlayback();
      }
      expect(session.activePlaybackFrames, greaterThan(beforeRouteChange));
      final checkpoint = session.activePlaybackFrames;
      session.interrupt(StopReason.background);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(session.waitingForUser, true);
      expect(session.activePlaybackFrames, checkpoint);
      audio.threshold = 24000; // Resumed route needs 500 ms to start.
      await session.continueSession();
      for (var pump = 0; pump < 10; pump++) {
        await session.pumpPlayback();
      }
      expect(session.activePlaybackFrames, greaterThan(checkpoint));
      expect(session.engine!.currentAction, StimulusAction.binaural8);
      session.interrupt(StopReason.background);
      await session.finish();
      final saved = (await repo.listSessions()).single;
      expect(
        saved.manifest.durationSeconds,
        session.activePlaybackFrames / 48000,
      );
      expect(saved.manifest.stopReason, 'manual');
      expect(audio.largestPacket, lessThanOrEqualTo(9600 * 4));
      expect(audio.largestQueued, lessThanOrEqualTo(24000));
      expect(service.active, false);
    },
  );
  test(
    'a short manual stop ramp starts on the native sink without counting silent priming',
    () async {
      final audio = BufferedAudio();
      final (session, repo, service, _) = await setup(audio);
      expect(await session.start(muse: SilentMuse()), true);
      for (var pump = 0; pump < 10; pump++) {
        await session.pumpPlayback();
      }
      await session.finish();
      final saved = (await repo.listSessions()).single;
      expect(saved.manifest.stopReason, 'manual');
      expect(
        saved.manifest.durationSeconds,
        (audio.stoppedHeads.first + 7200) / 48000,
      );
      final finalPcm = audio.currentPackets.expand((packet) => packet).toList();
      expect(finalPcm.length, 12000 * 4);
      expect(finalPcm.skip(7200 * 4), everyElement(0));
      expect(service.active, false);
    },
  );
  test(
    'an underrun in the final short tail re-primes without extending 600 active seconds',
    () async {
      final audio = BufferedAudio()
        ..consumption = 9600
        ..recordPackets = false
        ..underRunFinalTail = true;
      final (session, repo, service, _) = await setup(audio);
      expect(await session.start(muse: SilentMuse()), true);
      for (var pump = 0; pump < 4000 && !session.engine!.terminal; pump++) {
        await session.pumpPlayback();
      }
      expect(session.engine!.terminal, true);
      await session.finish();
      final saved = (await repo.listSessions()).single;
      expect(saved.status, 'completed');
      expect(saved.manifest.durationSeconds, 600);
      expect(audio.finalUnderrunTriggered, true);
      expect(audio.accepted, greaterThan(MeditationProtocol.totalFrames));
      expect(session.acceptedPlaybackFrames, MeditationProtocol.totalFrames);
      expect(audio.lastPacket, everyElement(0));
      expect(audio.largestPacket, lessThanOrEqualTo(9600 * 4));
      expect(audio.largestQueued, lessThanOrEqualTo(12000));
      expect(service.active, false);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'unsupported startup buffering fails closed without rendering oversized backlog',
    () async {
      final audio = BufferedAudio()..threshold = 48001;
      final (session, repo, service, _) = await setup(audio);
      expect(await session.start(muse: SilentMuse()), true);
      await session.pumpPlayback();
      await session.finish();
      final saved = (await repo.listSessions()).single;
      expect(saved.manifest.stopReason, 'audioLost');
      expect(saved.manifest.durationSeconds, 0);
      expect(audio.accepted, 0);
      expect(session.error, contains('one-second bound'));
      expect(service.active, false);
    },
  );
  test(
    'focus loss during unacknowledged final padding keeps the content checkpoint',
    () async {
      final audio = BufferedAudio();
      final (session, repo, service, _) = await setup(audio);
      expect(await session.start(muse: SilentMuse()), true);
      for (var pump = 0; pump < 10; pump++) {
        await session.pumpPlayback();
      }
      audio.holdPadding = true;
      final finishing = session.finish();
      for (var tick = 0; tick < 2000 && audio.pending == null; tick++) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(audio.pending, isNotNull);
      audio.played = 2400; // The primed track consumes part of the actual ramp.
      audio.events.add(const PcmInterruption('focus_loss_transient'));
      await finishing;
      final saved = (await repo.listSessions()).single;
      expect(saved.manifest.stopReason, 'manual');
      expect(
        saved.manifest.durationSeconds,
        (audio.stoppedHeads.first + 2400) / 48000,
      );
      expect(saved.manifest.interruptions, 0);
      expect(service.active, false);
      expect(audio.focusOwned, false);
    },
  );
}
