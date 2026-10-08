import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurotune/data/database.dart';
import 'package:neurotune/data/repository.dart';
import 'package:neurotune/data/meditation_action_repository.dart';
import 'package:neurotune/session/session_controller.dart';
import 'package:neurotune_core/neurotune_core.dart';
import 'meditation_session_test.dart'
    show ClockedPlaybackAudio, KeepAlive, SilentMuse;
import 'profile_library_test.dart' show metadata, wave, owner;

PersonalEegModel modelFor(
  AudioProfileVersion profile, {
  double alternative = 6.5,
}) {
  final json = Map<String, dynamic>.from(
    (jsonDecode(
              File(
                '../contracts/fixtures/personal_eeg.json',
              ).readAsStringSync(),
            )
            as Map)['model']
        as Map,
  );
  json['origin'] = 'muse';
  json['owner_account_id'] = owner;
  json['backgrounds'] = [profile.backgroundAssetId];
  json['feature_order'] = [
    'log_theta_alpha',
    'log_beta_alpha',
    'carrier_hz',
    'tone_gain',
    'background_gain',
    'background:${profile.backgroundAssetId}',
    'eye:closed',
  ];
  json['coefficients'] = [1, 0, 0, 0, 0, 0, 0];
  json['means'] = [0, 0, 0, 0, 0, 0, 0];
  json['scales'] = [1, 1, 1, 1, 1, 1, 1];
  json['intercept'] = 6;
  json['supported_contexts'] = [
    {
      'background_asset_id': profile.backgroundAssetId,
      'eye_state': 'closed',
      'session_count': 20,
    },
  ];
  final sid = (json['included_session_ids'] as List).first;
  json['fixed_minutes'] = [
    {
      'session_id': sid,
      'profile_version_id': profile.id,
      'background_asset_id': profile.backgroundAssetId,
      'eye_state': 'closed',
      'carrier_hz': profile.carrierHz,
      'tone_gain': profile.toneGain,
      'background_gain': profile.backgroundGain,
      'fixed_action': 'binaural_12',
      'minute': 0,
      'features': [alternative - 6, 0.0],
      'score': alternative,
    },
  ];
  return PersonalEegModel.fromJson(json);
}

FeatureFrame liveFrame(double time) => FeatureFrame.fromJson({
  'time_seconds': time,
  'sample_rate_hz': 256,
  'rejected': false,
  'reasons': [],
  'channels': [
    for (final name in ['EEG1', 'EEG2'])
      {
        'name': name,
        'contact': 4,
        'total_power': 4.0,
        'absolute_theta': 1.0,
        'absolute_alpha': 1.0,
        'absolute_beta': 1.0,
        'relative_theta': 0.2,
        'relative_alpha': 0.1,
        'relative_beta': 0.1,
        'valid': true,
        'reasons': [],
      },
  ],
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'statistics restart retains owned exact-setup model contributions without NIR pooling',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final sessions = SessionRepository(db);
      final repository = MeditationActionRepository(db, sessions);
      final profile = AudioProfileVersion.fromJson(metadata(wave()));
      final setup = MeditationSetupContext(
        profile: profile,
        eyeState: EyeState.closed,
        origin: DataOrigin.muse,
      );
      final model = modelFor(profile);
      final stats = await repository.load(owner, setup, model);
      expect(stats.counts[StimulusAction.binaural12], 1);
      expect(stats.means.containsKey(StimulusAction.control), false);
      stats.observe('adaptive', 0, StimulusAction.binaural6, 6);
      stats.observe(
        'adaptive',
        0,
        StimulusAction.binaural6,
        6,
      ); // Retry is idempotent.
      expect(await repository.save(stats, isCurrent: () => true), true);
      await sessions.bumpEvidenceEpoch(
        owner,
      ); // Freshness is not cached usability.
      final restored = await MeditationActionRepository(
        db,
        sessions,
      ).load(owner, setup, model);
      expect(restored.counts[StimulusAction.binaural6], 1);
      expect(restored.means[StimulusAction.binaural6], 6);
      expect(
        restored.contributions
            .where((c) => c['kind'] == 'adaptive')
            .single['session_id'],
        'adaptive',
      );
      expect(
        restored.includedSessionIds,
        containsAll([...model.includedSessionIds, 'adaptive']),
      );
      final next = PersonalEegModel.fromJson({
        ...model.toJson(),
        'model_version': 'v2',
      });
      expect(
        (await repository.load(
          owner,
          setup,
          next,
        )).counts[StimulusAction.binaural6],
        0,
      );
      final other = MeditationSetupContext(
        profile: profile,
        eyeState: EyeState.open,
        origin: DataOrigin.muse,
      );
      expect(
        (await repository.load(
          owner,
          other,
          model,
        )).counts.values.every((n) => n == 0),
        true,
      );
      expect(
        () => restored.observe('bad', 1, StimulusAction.control, double.nan),
        throwsFormatException,
      );
    },
  );
  test(
    'eligible cached model learns minute one and glides after already owned PCM',
    () async {
      final dir = await Directory.systemTemp.createTemp('adaptive-session');
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      addTearDown(() => dir.delete(recursive: true));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => dir.path,
          );
      final bytes = wave();
      final profile = AudioProfileVersion.fromJson(metadata(bytes));
      final file = await File('${dir.path}/sound.wav').writeAsBytes(bytes);
      final audio = ClockedPlaybackAudio();
      var observed = 0.0;
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
        mode: SessionMode.personal,
        eyeState: EyeState.closed,
        origin: DataOrigin.muse,
        observedTimeSeconds: () => observed,
        randomUnit: () => .9,
        meditation: MeditationSetup(
          profile: profile,
          file: file,
          action: StimulusAction.binaural6,
          model: modelFor(profile),
          metadata: {'owner_account_id': owner},
        ),
      );
      addTearDown(session.dispose);
      expect(await session.start(muse: SilentMuse()), true);
      await session.pumpPlayback();
      final protocol = session.engine! as MeditationProtocol;
      protocol.sourceAnchor(0, 0);
      // Controller source/DSP public input: raw endpoint clocks stay unchanged.
      for (var tick = 1; tick <= 400; tick++) {
        observed = tick * .15;
        audio.played = (observed * 48000).round();
        if (tick % 7 == 0) protocol.queueFrame(liveFrame(observed));
        await session.pumpPlayback();
      }
      expect(protocol.currentAction, StimulusAction.binaural12);
      final decision =
          protocol.manifest().meditation!['adaptive_decisions'] as List;
      expect(decision.single['score'], 6);
      expect(
        decision.single['probabilities']['binaural_12'],
        closeTo(.92, 1e-12),
      );
      expect(
        decision.single['transition_start_frame'],
        greaterThanOrEqualTo(60 * 48000),
      );
      expect(decision.single['transition_duration_frames'], 5 * 48000);
      session.interrupt(StopReason.background);
      await session.finish();
      final saved = (await session.repository.listSessions()).single;
      expect(saved.manifest.meditation!['mode'], 'adaptive');
      expect(saved.manifest.meditation!['model_version'], 'v1');
      expect(
        saved.decisions,
        isEmpty,
      ); // Separate from NIR decisions/statistics.
    },
  );
}
