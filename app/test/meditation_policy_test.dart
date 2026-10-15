import 'package:flutter_test/flutter_test.dart';
import 'package:neurotune_core/neurotune_core.dart';
import 'meditation_adaptation_test.dart' show modelFor, liveFrame;
import 'profile_library_test.dart' show metadata, wave, owner;

void main() {
  for (final (advantage, target) in [
    (0.49, StimulusAction.binaural6),
    (0.5, StimulusAction.binaural12),
    (0.51, StimulusAction.binaural12),
  ]) {
    test('literal advantage$advantage uses .92/.02 five-arm selection', () {
      final profile = AudioProfileVersion.fromJson(metadata(wave()));
      final stats = MeditationActionStatistics.seeded(
        owner,
        MeditationSetupContext(
          profile: profile,
          eyeState: EyeState.closed,
          origin: DataOrigin.muse,
        ),
        modelFor(profile, alternative: 6 + advantage),
      );
      final policy = MeditationAdaptation(
        statistics: stats,
        initialAction: StimulusAction.binaural6,
        randomUnit: () => .9,
      );
      final result = policy.evaluate(
        sessionId: 'adaptive-review',
        playedFrames: 60 * 48000,
        ownedFrames: 60 * 48000 + 7200,
        frames: [
          for (var s = 11; s <= 60; s++)
            liveFrame(s.toDouble()).withPlayback(s.toDouble(), true),
        ],
      )!;
      expect(policy.action, target);
      expect(result['score'], 6);
      final probabilities = result['probabilities'] as Map;
      expect(probabilities[target.id], .92);
      for (final a in fixedActionOrder.where((a) => a != target)) {
        expect(probabilities[a.id], .02);
      }
      expect(
        probabilities.values.fold<double>(
          0,
          (v, p) => v + (p as num).toDouble(),
        ),
        closeTo(1, 1e-12),
      );
      expect(stats.means.containsKey(StimulusAction.control), false);
      expect(stats.counts[StimulusAction.control], 0);
      expect(
        result['transition_start_frame'],
        target == StimulusAction.binaural6 ? null : 60 * 48000 + 7200,
      );
    });
  }
  test(
    'missing coverage holds with probability1 and never samples or learns unknown arms',
    () {
      final profile = AudioProfileVersion.fromJson(metadata(wave()));
      final stats = MeditationActionStatistics.seeded(
        owner,
        MeditationSetupContext(
          profile: profile,
          eyeState: EyeState.closed,
          origin: DataOrigin.muse,
        ),
        modelFor(profile),
      );
      final policy = MeditationAdaptation(
        statistics: stats,
        initialAction: StimulusAction.binaural6,
        randomUnit: () => throw StateError('quality hold must not sample'),
      );
      final result = policy.evaluate(
        sessionId: 'adaptive-review',
        playedFrames: 60 * 48000,
        ownedFrames: 60 * 48000,
        frames: const [],
      )!;
      expect(policy.action, StimulusAction.binaural6);
      expect(result['updated_statistics'], false);
      expect(result['score'], isNull);
      expect(result['probabilities'], {'binaural_6': 1});
      expect(stats.counts[StimulusAction.binaural6], 0);
    },
  );
  test(
    'a non-finite prediction from finite artifact parameters holds audio and skips learning',
    () {
      final profile = AudioProfileVersion.fromJson(metadata(wave()));
      final base = modelFor(profile);
      final model = PersonalEegModel.fromJson({
        ...base.toJson(),
        'coefficients': [1e308, 0, 0, 0, 0, 0, 0],
      });
      final stats = MeditationActionStatistics.seeded(
        owner,
        MeditationSetupContext(
          profile: profile,
          eyeState: EyeState.closed,
          origin: DataOrigin.muse,
        ),
        model,
      );
      final policy = MeditationAdaptation(
        statistics: stats,
        initialAction: StimulusAction.binaural6,
        randomUnit: () => throw StateError('invalid score must not sample'),
      );
      final frames = [
        for (var s = 11; s <= 60; s++)
          FeatureFrame.fromJson({
            ...liveFrame(
              s.toDouble(),
            ).withPlayback(s.toDouble(), true).toJson(),
            'channels': [
              for (final c in liveFrame(s.toDouble()).channels)
                {...c.toJson(), 'absolute_theta': 100.0},
            ],
          }),
      ];
      final result = policy.evaluate(
        sessionId: 'adaptive-review',
        playedFrames: 60 * 48000,
        ownedFrames: 60 * 48000,
        frames: frames,
      )!;
      expect(result['score'], isNull);
      expect(result['updated_statistics'], false);
      expect(policy.action, StimulusAction.binaural6);
      expect(stats.counts[StimulusAction.binaural6], 0);
      expect(result['probabilities'], {'binaural_6': 1});
    },
  );
}
