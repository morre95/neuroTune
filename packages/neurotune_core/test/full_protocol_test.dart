import 'package:neurotune_core/neurotune_core.dart';
import 'package:test/test.dart';

/// The other protocol tests shorten the contract so they run fast, which left
/// the shipped values (120 s baseline, 15 blocks of 30 s) untested end to end.
void main() {
  test('the shipped contract runs to completion and records every block', () {
    final config = ExperimentConfig.defaults();
    final engine = SessionEngine(
      config: config,
      snapshot: BanditSnapshot.empty(
        experimentVersion: config.version,
        origin: DataOrigin.simulator,
      ),
      sessionId: 'full',
      origin: DataOrigin.simulator,
      mode: SessionMode.personal,
      eyeState: EyeState.closed,
      sampleRateHz: 256,
      channelNames: simulatorChannels,
      seed: 7,
      startedAt: DateTime.utc(2026, 9, 24),
    );
    final source = SimulatorSource(config: config, sampleRateHz: 256, seed: 7);
    final pipeline = DspPipeline(
      config: config,
      sampleRateHz: 256,
      channelNames: simulatorChannels,
    );
    final optics = OpticsAccumulator();

    while (!engine.terminal && source.clock < 1800) {
      source.action = engine.currentAction;
      for (final frame in pullFrames(
        source: source,
        pipeline: pipeline,
        optics: optics,
      )) {
        engine.onFrame(frame);
      }
    }

    expect(engine.phase, SessionPhase.completed);
    expect(engine.stopReason, isNull);
    expect(engine.decisions.length, config.blockCount);
    expect(engine.completedBlocks, config.blockCount);
    expect(engine.manifest().stopReason, isNull);
    expect(engine.manifest().durationSeconds, greaterThan(700));
    expect(engine.manifest().endedInPhase, 'completed');
    expect(engine.manifest().interruptions, 0);
  });

  test('a session left waiting for a stable signal says so', () {
    final config = ExperimentConfig.defaults().withProtocol(
      baselineSeconds: 12,
      blockCount: 2,
      soundSeconds: 6,
      pauseSeconds: 1,
      rewardTailSeconds: 4,
    );
    final engine = SessionEngine(
      config: config,
      snapshot: BanditSnapshot.empty(
        experimentVersion: config.version,
        origin: DataOrigin.simulator,
      ),
      sessionId: 'waiting',
      origin: DataOrigin.simulator,
      mode: SessionMode.personal,
      eyeState: EyeState.closed,
      sampleRateHz: 256,
      channelNames: simulatorChannels,
      seed: 7,
      startedAt: DateTime.utc(2026, 9, 24),
    );
    final source = SimulatorSource(config: config, sampleRateHz: 256, seed: 7);
    final pipeline = DspPipeline(
      config: config,
      sampleRateHz: 256,
      channelNames: simulatorChannels,
    );
    final optics = OpticsAccumulator();

    // Run past the baseline so channels are selected and a block is running.
    while (engine.phase != SessionPhase.sound && source.clock < 60) {
      source.action = engine.currentAction;
      for (final frame in pullFrames(
        source: source,
        pipeline: pipeline,
        optics: optics,
      )) {
        engine.onFrame(frame);
      }
    }
    expect(engine.manifest().selectedChannels, isNotEmpty);

    // Three dropouts: the first pauses the block, the rest land while paused.
    engine.interrupt(StopReason.sourceDisconnected);
    engine.interrupt(StopReason.sourceDisconnected);
    engine.interrupt(StopReason.manual);

    final manifest = engine.manifest();
    expect(engine.phase, SessionPhase.waitingStable);
    expect(manifest.stopReason, isNull);
    expect(manifest.endedInPhase, 'waitingStable');
    expect(manifest.interruptions, 3);
    expect(manifest.lastInterruptReason, 'manual');
  });

  test('a rejected baseline records why the session ended', () {
    final config = ExperimentConfig.defaults().withProtocol(baselineSeconds: 12);
    final engine = SessionEngine(
      config: config,
      snapshot: BanditSnapshot.empty(
        experimentVersion: config.version,
        origin: DataOrigin.simulator,
      ),
      sessionId: 'rejected',
      origin: DataOrigin.simulator,
      mode: SessionMode.personal,
      eyeState: EyeState.closed,
      sampleRateHz: 256,
      channelNames: simulatorChannels,
      seed: 7,
      startedAt: DateTime.utc(2026, 9, 24),
    );

    engine.interrupt(StopReason.manual);

    expect(engine.phase, SessionPhase.stopped);
    expect(engine.decisions, isEmpty);
    expect(engine.manifest().stopReason, 'manual');
    expect(engine.manifest().selectedChannels, isEmpty);
  });
}
