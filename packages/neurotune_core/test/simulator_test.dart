import 'package:neurotune_core/neurotune_core.dart';
import 'package:test/test.dart';

void main() {
  test('gaps, saturation, motion, and flatline invalidate windows', () {
    final config = ExperimentConfig.defaults();
    for (final scenario in [
      SimulatorScenario.gaps,
      SimulatorScenario.saturation,
      SimulatorScenario.motion,
      SimulatorScenario.flatline,
    ]) {
      final pipeline = DspPipeline(
        config: config,
        sampleRateHz: 256,
        channelNames: simulatorChannels,
      );
      final source = SimulatorSource(config: config, sampleRateHz: 256, seed: 1, scenario: scenario);
      final frames = <FeatureFrame>[];
      final horizon = scenario == SimulatorScenario.gaps ? 14.0 : 8.0;
      while (source.clock < horizon) {
        frames.addAll(pipeline.addBatch(source.pull()));
      }
      expect(frames.any((frame) => frame.rejected || frame.channels.any((channel) => !channel.valid)), isTrue,
          reason: scenario.name);
    }
  });

  test('corruption during the reward window does not update the bandit', () {
    final config = ExperimentConfig.defaults().withProtocol(
      baselineSeconds: 12,
      blockCount: 2,
      soundSeconds: 6,
      pauseSeconds: 1,
      rewardTailSeconds: 4,
    );
    final snapshot = BanditSnapshot.empty(experimentVersion: config.version, origin: DataOrigin.simulator);
    final engine = SessionEngine(
      config: config,
      snapshot: snapshot,
      sessionId: 'corrupt',
      origin: DataOrigin.simulator,
      mode: SessionMode.personal,
      eyeState: EyeState.closed,
      sampleRateHz: 256,
      channelNames: simulatorChannels,
      seed: 4,
      startedAt: DateTime.utc(2026, 9, 23),
    );
    final source = SimulatorSource(
      config: config,
      sampleRateHz: 256,
      seed: 4,
      corruptAfterSeconds: config.baselineSeconds,
    );
    final pipeline = DspPipeline(config: config, sampleRateHz: 256, channelNames: simulatorChannels);
    var steps = 0;
    while (!engine.terminal && source.clock < 40 && steps < 100000) {
      source.action = engine.currentAction;
      for (final frame in pipeline.addBatch(source.pull())) {
        engine.onFrame(frame);
      }
      steps += 1;
    }
    expect(engine.phase, SessionPhase.completed);
    expect(engine.policy.stats.values.every((stat) => stat.n == 0), isTrue);
  });

  test('the bandit learns the simulated response and keeps exploring', () {
    final config = ExperimentConfig.defaults().withProtocol(
      baselineSeconds: 12,
      blockCount: 8,
      soundSeconds: 6,
      pauseSeconds: 1,
      rewardTailSeconds: 4,
    );
    final stats = {for (final action in StimulusAction.values) action: const ActionStat(0, 0)};
    final chosen = <String>{};
    for (var session = 0; session < 4; session++) {
      final engine = SessionEngine(
        config: config,
        snapshot: BanditSnapshot(
          policyVersion: 'local',
          experimentVersion: config.version,
          dataOrigin: DataOrigin.simulator.name,
          epsilon: config.epsilon,
          actions: stats,
          includedSessionIds: const [],
          createdAtIso: '2026-09-23T00:00:00Z',
        ),
        sessionId: 'learn-$session',
        origin: DataOrigin.simulator,
        mode: SessionMode.personal,
        eyeState: EyeState.open,
        sampleRateHz: 256,
        channelNames: simulatorChannels,
        seed: 20 + session,
        startedAt: DateTime.utc(2026, 9, 23),
      );
      final source = SimulatorSource(
        config: config,
        sampleRateHz: 256,
        seed: 20 + session,
        scenario: SimulatorScenario.response,
      );
      final pipeline = DspPipeline(config: config, sampleRateHz: 256, channelNames: simulatorChannels);
      var steps = 0;
      while (!engine.terminal && source.clock < 120 && steps < 200000) {
        source.action = engine.currentAction;
        for (final frame in pipeline.addBatch(source.pull())) {
          engine.onFrame(frame);
        }
        steps += 1;
      }
      expect(engine.phase, SessionPhase.completed, reason: 'session $session');
      for (final action in StimulusAction.values) {
        stats[action] = engine.policy.stats[action]!;
      }
      chosen.addAll(engine.decisions.map((decision) => decision.action));
    }
    final best = stats.entries.reduce((a, b) => a.value.mean >= b.value.mean ? a : b).key;
    expect(best, StimulusAction.binaural10);
    expect(stats[StimulusAction.binaural10]!.n, greaterThan(0));
    expect(chosen, contains('binaural_10'));
    expect(chosen.length, greaterThan(1));
    expect(
      stats[StimulusAction.binaural10]!.mean,
      greaterThan(stats[StimulusAction.control]!.mean),
    );
  });

  test('recordings round-trip and playback emits the same batches', () async {
    final config = ExperimentConfig.defaults();
    final source = SimulatorSource(config: config, sampleRateHz: 256, seed: 2, scenario: SimulatorScenario.tones);
    final original = [source.pull(), source.pull()];
    final restored = decodeBatches(encodeBatches(original));
    expect(restored.first.sampleRateHz, original.first.sampleRateHz);
    expect(restored.first.eeg.first.first, closeTo(original.first.eeg.first.first, 1e-9));
    final playback = PlaybackSource(restored);
    final emitted = playback.batches.take(2).toList();
    await playback.start();
    expect(await emitted, hasLength(2));
  });

  test('Muse stays unavailable until hardware is approved', () async {
    final source = MuseSource(ExperimentConfig.defaults());
    expect(source.start, throwsA(isA<MuseUnavailable>()));
  });
}
