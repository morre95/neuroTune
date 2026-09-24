import 'dart:math';

import 'bandit.dart';
import 'dsp/pipeline.dart';
import 'models.dart';

class SessionEngine {
  SessionEngine({
    required this.config,
    required BanditSnapshot snapshot,
    required this.sessionId,
    required this.origin,
    required this.mode,
    required this.eyeState,
    required this.sampleRateHz,
    required this.channelNames,
    required this.seed,
    required this.startedAt,
    Random? random,
  }) : policy = EpsilonPolicy(
         epsilon: snapshot.epsilon,
         random: random ?? Random(seed),
         stats: snapshot.actions,
       ),
       policyVersion = snapshot.policyVersion {
    if (mode == SessionMode.personal) {
      _warmup = [...StimulusAction.values]..shuffle(policy.random);
    }
  }

  final ExperimentConfig config;
  final String sessionId;
  final DataOrigin origin;
  final SessionMode mode;
  final EyeState eyeState;
  final double sampleRateHz;
  final List<String> channelNames;
  final int seed;
  final DateTime startedAt;
  final EpsilonPolicy policy;
  final String policyVersion;

  final List<FeatureFrame> frames = [];
  final List<DecisionEvent> decisions = [];
  final List<FeatureFrame> _baseline = [];
  final List<FeatureFrame> _reward = [];

  SessionPhase phase = SessionPhase.baseline;
  StopReason? stopReason;

  /// Every signal loss, not only the ones that end the session. A session that
  /// never leaves [SessionPhase.waitingStable] ends with no stop reason at all,
  /// so without these the recording cannot say why it produced no blocks.
  int interruptions = 0;
  StopReason? lastInterruption;
  String message = 'Baslinje pågår. Håll samma ögonläge.';
  StimulusAction? currentAction;
  List<String> selectedChannels = [];
  double baselineMean = 0;
  double baselineStd = 0;
  int completedBlocks = 0;

  List<StimulusAction> _warmup = [];
  List<StimulusAction> _comparisonCycle = [];
  double _soundStart = 0;
  double _soundEnd = 0;
  double _pauseEnd = 0;
  int _attempts = 0;
  int _stableCount = 0;
  bool _resumeRequested = false;
  double _lastTime = 0;
  bool _blockAborted = false;

  bool get terminal =>
      phase == SessionPhase.completed || phase == SessionPhase.stopped;

  void onFrame(FeatureFrame frame) {
    if (terminal) return;
    frames.add(frame);
    _lastTime = frame.timeSeconds;
    var guard = 0;
    while (!terminal && guard < 4) {
      final before = phase;
      _step(frame);
      if (phase == before) break;
      guard += 1;
    }
  }

  void interrupt(StopReason reason) {
    if (terminal) return;
    interruptions += 1;
    lastInterruption = reason;
    if (phase == SessionPhase.waitingStable) return;
    if (phase == SessionPhase.baseline) {
      _stop(reason, 'Baslinjen avbröts. Starta en ny session.');
      return;
    }
    if (phase == SessionPhase.sound) {
      _closeBlock(aborted: true, reason: reason);
    }
    currentAction = null;
    phase = SessionPhase.waitingStable;
    _stableCount = 0;
    _resumeRequested = false;
    message = 'Signalen avbröts. Väntar på en stabil signal innan nästa block.';
  }

  void resume() {
    if (phase != SessionPhase.waitingStable) return;
    _stableCount = 0;
    _resumeRequested = true;
  }

  SessionManifest manifest({double? audioLatencyMs, String checksum = ''}) {
    return SessionManifest(
      sessionId: sessionId,
      userId: null,
      experimentVersion: config.version,
      policyVersion: policyVersion,
      dataOrigin: origin.name,
      mode: mode.name,
      eyeState: eyeState.name,
      sampleRateHz: sampleRateHz,
      channelNames: channelNames,
      selectedChannels: selectedChannels,
      startedAtIso: startedAt.toUtc().toIso8601String(),
      durationSeconds: frames.isEmpty ? 0 : frames.last.timeSeconds,
      audioLatencyMs: audioLatencyMs,
      audioLatencySource: 'audiotrack_buffer_frames',
      timeline: 'monotonic_session_seconds',
      seed: seed,
      checksumSha256: checksum,
      stopReason: stopReason?.name,
      endedInPhase: phase.name,
      interruptions: interruptions,
      lastInterruptReason: lastInterruption?.name,
    );
  }

  LocalSessionRewards get localRewards => LocalSessionRewards(
    sessionId: sessionId,
    origin: origin,
    experimentVersion: config.version,
    personal: mode == SessionMode.personal,
    rewards: [
      for (final decision in decisions)
        if (decision.updatedBandit && decision.reward != null)
          LocalReward(StimulusAction.byId(decision.action), decision.reward!),
    ],
  );

  void _step(FeatureFrame frame) {
    switch (phase) {
      case SessionPhase.baseline:
        if (frame.timeSeconds <= config.baselineSeconds) _baseline.add(frame);
        if (frame.timeSeconds >= config.baselineSeconds) _finishBaseline();
      case SessionPhase.sound:
        if (_inReward(frame.timeSeconds)) _reward.add(frame);
        if (frame.timeSeconds >= _soundEnd) {
          _closeBlock(aborted: false);
          phase = SessionPhase.pause;
          currentAction = null;
          message = 'Tyst paus.';
        }
      case SessionPhase.pause:
        if (frame.timeSeconds >= _pauseEnd) _afterPause();
      case SessionPhase.waitingStable:
        if (!_resumeRequested) break;
        final stable = _aggregate(frame, selectedChannels) != null;
        _stableCount = stable ? _stableCount + 1 : 0;
        if (_stableCount >= config.stableFramesRequired) {
          _resumeRequested = false;
          _startSound(frame.timeSeconds);
        }
      case SessionPhase.completed:
      case SessionPhase.stopped:
        break;
    }
  }

  void _finishBaseline() {
    final selected = <String>[];
    for (final name in config.outerNirChannels) {
      if (_baseline.isEmpty) continue;
      final valid = _baseline.where((frame) => frame.opticsValid(name)).length;
      if (valid / _baseline.length >= config.minBaselineValidFraction) {
        selected.add(name);
      }
    }
    if (selected.length < config.minChannels) {
      _stop(
        StopReason.baselineFailed,
        'För få godkända kanaler. Gör om baslinjen.',
      );
      return;
    }
    final values = <double>[];
    for (final frame in _baseline) {
      final sample = _aggregate(frame, selected);
      if (sample != null) values.add(sample);
    }
    if (values.length < 2 ||
        values.length / _baseline.length < config.minBaselineValidFraction) {
      _stop(StopReason.baselineFailed, 'Baslinjen har för lite giltig data.');
      return;
    }
    final std = populationStd(values);
    if (std < config.minBaselineStd) {
      _stop(
        StopReason.baselineFailed,
        'Baslinjen varierar nästan inte. Gör om baslinjen.',
      );
      return;
    }
    selectedChannels = selected;
    baselineMean = meanOf(values);
    baselineStd = std;
    _startSound(config.baselineSeconds);
  }

  void _startSound(double at) {
    if (completedBlocks >= config.blockCount) {
      phase = SessionPhase.completed;
      currentAction = null;
      message = 'Sessionen är klar.';
      return;
    }
    if (_attempts >= config.blockCount + config.maxExtraAttempts) {
      _stop(
        StopReason.attemptLimit,
        'Sessionen stoppades efter för många avbrutna block.',
      );
      return;
    }
    final choice = _nextChoice();
    _attempts += 1;
    _soundStart = at;
    _soundEnd = at + config.soundSeconds;
    _pauseEnd = _soundEnd + config.pauseSeconds;
    _reward.clear();
    _blockAborted = false;
    currentAction = choice.action;
    phase = SessionPhase.sound;
    message = 'Ljudblock $_attempts.';
    _pendingChoice = choice;
  }

  ActionChoice? _pendingChoice;

  ActionChoice _nextChoice() {
    if (mode == SessionMode.comparison) {
      if (_comparisonCycle.isEmpty) {
        _comparisonCycle = [...StimulusAction.values]..shuffle(policy.random);
      }
      return ActionChoice(
        _comparisonCycle.removeAt(0),
        1 / StimulusAction.values.length,
      );
    }
    if (_warmup.isNotEmpty) {
      final probability = 1 / _warmup.length;
      return ActionChoice(_warmup.removeAt(0), probability);
    }
    return policy.select();
  }

  bool _inReward(double time) {
    final start = _soundStart + config.soundSeconds - config.rewardTailSeconds;
    return time > start && time <= _soundEnd;
  }

  void _closeBlock({required bool aborted, StopReason? reason}) {
    if (_pendingChoice == null || _blockAborted) return;
    final expected = max(
      1,
      (config.rewardTailSeconds / config.welchHopSeconds).round(),
    );
    final validFrames = [
      for (final frame in _reward)
        if (_aggregate(frame, selectedChannels) != null) frame,
    ];
    final fraction = validFrames.length / expected;
    double? reward;
    double? absolute;
    double? outerNir;
    var updated = false;
    if (!aborted && fraction >= config.minValidFraction) {
      final scores = [
        for (final frame in validFrames)
          (_aggregate(frame, selectedChannels)! - baselineMean) / baselineStd,
      ];
      reward = meanOf(
        scores,
      ).clamp(-config.rewardClip, config.rewardClip).toDouble();
      outerNir = meanOf([
        for (final frame in validFrames) _aggregate(frame, selectedChannels)!,
      ]);
      final theta = [
        for (final frame in validFrames)
          if (_absoluteTheta(frame) != null) _absoluteTheta(frame)!,
      ];
      absolute = theta.isEmpty ? null : meanOf(theta);
      if (mode == SessionMode.personal) {
        policy.observe(_pendingChoice!.action, reward);
        updated = true;
      }
      completedBlocks += 1;
    } else if (!aborted) {
      completedBlocks += 1;
    }
    decisions.add(
      DecisionEvent(
        sessionId: sessionId,
        blockIndex: decisions.length,
        attemptIndex: _attempts - 1,
        action: _pendingChoice!.action.id,
        selectionProbability: _pendingChoice!.probability,
        reward: reward,
        meanAbsoluteTheta: absolute,
        meanOuterNir: outerNir,
        validFraction: fraction,
        updatedBandit: updated,
        experimentVersion: config.version,
        policyVersion: policyVersion,
        qualityVersion: config.qualityVersion,
        startedAtSeconds: _soundStart,
        endedAtSeconds: aborted ? _lastTime : _soundEnd,
        aborted: aborted,
        abortReason: reason?.name,
      ),
    );
    _blockAborted = aborted;
    if (aborted) _pendingChoice = null;
  }

  void _afterPause() {
    _pendingChoice = null;
    if (completedBlocks >= config.blockCount) {
      phase = SessionPhase.completed;
      currentAction = null;
      message = 'Sessionen är klar.';
      return;
    }
    _startSound(_pauseEnd);
  }

  void _stop(StopReason reason, String text) {
    phase = SessionPhase.stopped;
    stopReason = reason;
    currentAction = null;
    message = text;
  }

  double? _aggregate(FeatureFrame frame, List<String> channels) {
    if (channels.isEmpty) return null;
    final values = <double>[];
    for (final name in channels) {
      final reading = frame.optics.where((channel) => channel.name == name);
      if (reading.isEmpty || !reading.first.valid) return null;
      values.add(reading.first.intensity);
    }
    return meanOf(values);
  }

  double? _absoluteTheta(FeatureFrame frame) {
    final values = <double>[];
    for (final name in selectedChannels) {
      if (!frame.channelValid(name)) continue;
      values.add(
        frame.channels
            .firstWhere((channel) => channel.name == name)
            .absoluteTheta,
      );
    }
    if (values.isEmpty) return null;
    return meanOf(values);
  }
}
