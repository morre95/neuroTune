import 'dart:math';

import 'package:neurotune_core/neurotune_core.dart';
import 'package:test/test.dart';

void main() {
  test('a twelve minute session completes fifteen blocks', () {
    final engine = _engine();
    for (var second = 4; second <= 720; second++) {
      engine.onFrame(_frame(second.toDouble()));
    }
    expect(engine.phase, SessionPhase.completed);
    expect(engine.completedBlocks, 15);
    expect(engine.decisions.where((decision) => !decision.aborted), hasLength(15));
    expect(engine.decisions.take(5).map((decision) => decision.action).toSet(), hasLength(5));
    expect(engine.decisions.every((decision) => decision.updatedBandit), isTrue);
    expect(engine.manifest().timeline, 'monotonic_session_seconds');
    expect(engine.manifest().durationSeconds, 720);
  });

  test('artifacts leave the bandit unchanged', () {
    final engine = _engine();
    for (var second = 4; second <= 720; second++) {
      final inReward = _inAnyReward(second.toDouble());
      engine.onFrame(_frame(second.toDouble(), valid: !inReward));
    }
    expect(engine.phase, SessionPhase.completed);
    expect(engine.policy.stats.values.every((stat) => stat.n == 0), isTrue);
    expect(engine.decisions.every((decision) => decision.reward == null), isTrue);
  });

  test('an aborted block gives no reward and the next block is new', () {
    final engine = _engine();
    for (var second = 4; second <= 125; second++) {
      engine.onFrame(_frame(second.toDouble()));
    }
    expect(engine.phase, SessionPhase.sound);
    final first = engine.currentAction;
    engine.interrupt(StopReason.manual);
    expect(engine.decisions.single.aborted, isTrue);
    expect(engine.decisions.single.reward, isNull);
    expect(engine.policy.stats[first]!.n, 0);
    for (var second = 126; second <= 130; second++) {
      engine.onFrame(_frame(second.toDouble()));
    }
    expect(engine.phase, SessionPhase.sound);
    expect(engine.decisions, hasLength(1));
    expect(engine.currentAction, isNotNull);
  });

  test('almost no baseline variation asks for a new baseline', () {
    final engine = _engine();
    for (var second = 4; second <= 120; second++) {
      engine.onFrame(_frame(second.toDouble(), theta: 0.2));
    }
    expect(engine.phase, SessionPhase.stopped);
    expect(engine.stopReason, StopReason.baselineFailed);
  });

  test('comparison mode records blocks without updating the policy', () {
    final engine = _engine(mode: SessionMode.comparison);
    for (var second = 4; second <= 720; second++) {
      engine.onFrame(_frame(second.toDouble()));
    }
    expect(engine.completedBlocks, 15);
    expect(engine.policy.stats.values.every((stat) => stat.n == 0), isTrue);
    final counts = <String, int>{};
    for (final decision in engine.decisions) {
      counts[decision.action] = (counts[decision.action] ?? 0) + 1;
    }
    expect(counts.values.toSet(), {3});
  });

  test('a lost source during baseline stops the session', () {
    final engine = _engine();
    engine.onFrame(_frame(4));
    engine.interrupt(StopReason.sourceDisconnected);
    expect(engine.phase, SessionPhase.stopped);
    expect(engine.decisions, isEmpty);
  });
}

bool _inAnyReward(double second) {
  for (var block = 0; block < 15; block++) {
    final soundStart = 120 + block * 40;
    final rewardStart = soundStart + 10;
    final soundEnd = soundStart + 30;
    if (second > rewardStart && second <= soundEnd) return true;
  }
  return false;
}

SessionEngine _engine({SessionMode mode = SessionMode.personal}) {
  final config = ExperimentConfig.defaults();
  return SessionEngine(
    config: config,
    snapshot: BanditSnapshot.empty(experimentVersion: config.version, origin: DataOrigin.simulator),
    sessionId: 'session-1',
    origin: DataOrigin.simulator,
    mode: mode,
    eyeState: EyeState.open,
    sampleRateHz: 256,
    channelNames: simulatorChannels,
    seed: 7,
    startedAt: DateTime.utc(2026, 9, 23),
  );
}

FeatureFrame _frame(double time, {bool valid = true, double? theta}) {
  final value = theta ?? (0.25 + 0.01 * sin(time));
  return FeatureFrame(
    timeSeconds: time,
    sampleRateHz: 256,
    rejected: !valid,
    reasons: valid ? const [] : const ['saturation'],
    channels: [
      for (final name in simulatorChannels)
        ChannelFeature(
          name: name,
          valid: valid,
          contact: valid ? 1 : 4,
          absoluteTheta: 12,
          absoluteAlpha: 8,
          absoluteBeta: 4,
          relativeTheta: value,
          relativeAlpha: 0.2,
          relativeBeta: 0.1,
          totalPower: 30,
          reasons: valid ? const [] : const ['saturation'],
        ),
    ],
  );
}
