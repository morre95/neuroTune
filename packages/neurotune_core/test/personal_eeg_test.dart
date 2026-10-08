import 'dart:convert';
import 'dart:io';
import 'package:neurotune_core/neurotune_core.dart';
import 'package:test/test.dart';

void main() {
  final fixture =
      jsonDecode(
            File(
              '../../contracts/fixtures/personal_eeg.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  test(
    'minute extraction follows shared literal ratio coverage and fractional clocks',
    () {
      for (final c in fixture['extraction'] as List) {
        final frames = [
          for (var second = c['start'] as int; second <= c['end']; second++)
            FeatureFrame.fromJson({
              'time_seconds': second + (c['source_offset'] as num),
              'active_time_seconds': second + (c['active_offset'] as num),
              'playback_active': true,
              'sample_rate_hz': 256,
              'rejected': false,
              'reasons': [],
              'optics': [],
              'channels': [
                for (final channel in fixture['ratio_channels'] as List)
                  {
                    ...channel as Map<String, dynamic>,
                    'contact': 0,
                    'relative_theta': 0,
                    'relative_alpha': 0,
                    'relative_beta': 0,
                    'total_power': 14,
                    'reasons': [],
                  },
              ],
            }),
        ];
        final minutes = extractMeditationMinutes(frames);
        expect(minutes.map((m) => m.minute).toList(), c['expected_minutes']);
        if (minutes.isNotEmpty) {
          expect(minutes.single.coverage, {
            'A': c['expected_coverage'],
            'B': c['expected_coverage'],
          });
          expect(
            minutes.single.features[0],
            closeTo(fixture['expected_ratios'][0], 1e-12),
          );
          expect(
            minutes.single.features[1],
            closeTo(fixture['expected_ratios'][1], 1e-12),
          );
        }
      }
    },
  );
  test(
    'versioned model inference uses literal coefficients and inclusive global ranges',
    () {
      final model = PersonalEegModel.fromJson(
        Map<String, dynamic>.from(fixture['model'] as Map),
      );
      for (final c in fixture['inference'] as List) {
        expect(
          model.predict(
            (c['features'] as List)
                .cast<num>()
                .map((v) => v.toDouble())
                .toList(),
            backgroundAssetId: model.backgrounds.single,
            eyeState: 'closed',
            carrierHz: 220,
            toneGain: .2,
            backgroundGain: .6,
          ),
          closeTo(c['prediction'], 1e-12),
        );
      }
      expect(
        model.unsupportedReason(
          backgroundAssetId: model.backgrounds.single,
          eyeState: 'closed',
          carrierHz: 220,
          toneGain: .2,
          backgroundGain: .6,
        ),
        isNull,
      );
      expect(
        model.unsupportedReason(
          backgroundAssetId: model.backgrounds.single,
          eyeState: 'open',
          carrierHz: 220,
          toneGain: .2,
          backgroundGain: .6,
        ),
        isNotNull,
      );
      expect(
        model.unsupportedReason(
          backgroundAssetId: model.backgrounds.single,
          eyeState: 'closed',
          carrierHz: 221,
          toneGain: .2,
          backgroundGain: .6,
        ),
        isNotNull,
      );
      final synthetic =
          jsonDecode(
                File(
                  '../../contracts/fixtures/synthetic_simulator_model.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final delivered = PersonalEegModel.fromJson(
        Map<String, dynamic>.from(synthetic['model'] as Map),
      );
      expect(delivered.status, 'ready');
      expect(delivered.validation['session_count'], 20);
      expect(delivered.origin, 'simulator');
      expect(
        delivered.predict(
          [1.5, -.1],
          backgroundAssetId: delivered.backgrounds.first,
          eyeState: 'closed',
          carrierHz: 220,
          toneGain: .2,
          backgroundGain: .6,
        ),
        closeTo(8.785714285714286, .2),
      );
      expect(
        () => PersonalEegModel.fromJson({
          ...model.toJson(),
          'coefficients': [double.nan],
        }),
        throwsFormatException,
      );
      expect(
        () => PersonalEegModel.fromJson({
          ...model.toJson(),
          'preprocessing_version': 'other',
        }),
        throwsFormatException,
      );
    },
  );
}
