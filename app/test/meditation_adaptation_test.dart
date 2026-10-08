import 'dart:async';
import 'package:neurotune/audio/meditation_renderer.dart';
import 'meditation_interruptions_test.dart' show InterruptedAudio;
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
    show PlaybackAudio, ClockedPlaybackAudio, KeepAlive, SilentMuse;
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

FeatureFrame liveFrame(double time, {double theta = 1.0}) =>
    FeatureFrame.fromJson({
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
            'absolute_theta': theta,
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
    'held PCM pause halfway through a glide preserves absolute phase and continuous source clock',
    () async {
      final output = InterruptedAudio();
      final h = await AdaptiveHarness.open(output: output);
      await h.advance(60);
      await h.advance(2.65);
      final decision = h.protocol.adaptation!.decisions.single;
      final glide = decision['transition_start_frame'] as int;
      // A newly rendered packet is partially played while its write is held.
      output.holdWrites = true;
      h.observed += .1;
      output.played = (62.75 * 48000).round();
      final held = h.session.pumpPlayback();
      while (output.pending == null) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      h.observed = 62.85;
      output.played = (62.85 * 48000).round();
      h.session.interrupt(StopReason.background);
      output.holdWrites = false;
      final packetIndex = output.packets.length;
      h.observed +=
          20; // No active time or policy updates during a focus pause.
      for (var t = 63; t <= 82; t++) {
        h.protocol.queueFrame(liveFrame(t.toDouble()));
      }
      h.nextSourceSecond = 83;
      await h.session.continueSession();
      await held;
      await h.session.pumpPlayback();
      h.base = h.session.activePlaybackFrames;
      expect(h.base, (62.85 * 48000).round());
      expect(h.protocol.adaptation!.decisions.length, 1);
      expect(h.protocol.currentAction, StimulusAction.binaural12);
      final r = await MeditationRenderer.open(
        h.session.meditation!.file,
        h.scope.profile,
        StimulusAction.binaural6,
      );
      await r.scheduleAction(glide, StimulusAction.binaural12);
      final resumed = output.packets[packetIndex];
      expect(resumed, await r.render(h.base, resumed.length ~/ 4));
      await r.close();
      await h.advance(57.15);
      expect(h.protocol.adaptation!.decisions.length, 2);
      expect(h.protocol.adaptation!.decisions.last['updated_statistics'], true);
      await h.stop();
      final saved = (await h.repository.listSessions()).single;
      expect(
        saved.frames
            .where((f) => f.timeSeconds >= 67 && f.timeSeconds <= 82)
            .every((f) => f.playbackActive == false),
        true,
      );
      expect(
        saved.frames.last.timeSeconds - saved.frames.last.activeTimeSeconds!,
        closeTo(20, 1e-6),
      );
    },
  );
  test(
    'serialized minute change starts beyond prior accepted PCM without overwriting the owned packet',
    () async {
      final output = InterruptedAudio();
      final h = await AdaptiveHarness.open(output: output);
      await h.advance(59.95);
      final owned = h.session.acceptedPlaybackFrames;
      expect(owned, greaterThan(60 * 48000));
      final packet = List<int>.of(output.packets.last);
      await h.advance(.05);
      final d = h.protocol.adaptation!.decisions.single;
      expect(d['transition_start_frame'], owned);
      expect(output.packets[output.packets.length - 2], packet);
      await h.stop();
    },
  );
  for (final duringWrite in [false, true]) {
    test(
      duringWrite
          ? 'statistics generation revocation during SQLite write rolls back'
          : 'queued statistics cannot publish after account switch',
      () async {
        var current = true;
        final db = AppDatabase(
          NativeDatabase.memory(
            setup: (sqlite) {
              sqlite.createFunction(
                functionName: 'revoke_stats_auth',
                directOnly: false,
                function: (_) {
                  current = false;
                  return 0;
                },
              );
            },
          ),
        );
        addTearDown(db.close);
        final sessions = SessionRepository(db),
            actions = MeditationActionRepository(db, SessionRepository(db));
        final profile = AudioProfileVersion.fromJson(metadata(wave()));
        final scope = MeditationSetupContext(
          profile: profile,
          eyeState: EyeState.closed,
          origin: DataOrigin.muse,
        );
        final stats = MeditationActionStatistics.seeded(
          owner,
          scope,
          modelFor(profile),
        );
        final key = actions.key(stats);
        if (duringWrite) {
          await db.customStatement(
            "CREATE TRIGGER revoke_stats AFTER INSERT ON kv_store WHEN NEW.key = '$key' BEGIN SELECT revoke_stats_auth(); END",
          );
          expect(await actions.save(stats, isCurrent: () => current), false);
        } else {
          final locked = Completer<void>(), release = Completer<void>();
          final barrier = db.transaction(() async {
            await db.getKv('barrier');
            locked.complete();
            await release.future;
          });
          await locked.future;
          final pending = actions.save(stats, isCurrent: () => current);
          current = false;
          release.complete();
          await barrier;
          expect(await pending, false);
        }
        expect(current, false);
        expect(await db.getKv(key), isNull);
        current = true;
        if (duringWrite) await db.customStatement('DROP TRIGGER revoke_stats');
        expect(await actions.save(stats, isCurrent: () => current), true);
        await sessions.enqueueUpload(
          stats.model.includedSessionIds.last,
          'a' * 64,
          'missing-owned-raw',
          'owner@test',
        );
        await sessions.deleteSessions(
          [stats.model.includedSessionIds.last],
          'owner@test',
          ownerAccountId: owner,
          cleanupRaw: false,
        );
        expect(
          await actions.save(stats, isCurrent: () => current),
          false,
          reason:
              'Full fitted evidence, not just exact-setup seed IDs, guards publication',
        );
      },
    );
  }
  test(
    'finite model overflow leaves controller audio active with unavailable score and no learning',
    () async {
      final h = await AdaptiveHarness.open(
        transformModel: (m) => PersonalEegModel.fromJson({
          ...m.toJson(),
          'coefficients': [1e308, 0, 0, 0, 0, 0, 0],
        }),
        random: () => throw StateError('Invalid inference must not sample'),
      );
      expect(h.protocol.adaptation, isNotNull);
      await h.advance(60, theta: 100);
      expect(h.audio.playing, true);
      expect(h.protocol.phase, SessionPhase.sound);
      expect(h.protocol.currentAction, StimulusAction.binaural6);
      final d = h.protocol.adaptation!.decisions.single;
      expect(d['quality']['eeg_eligible'], true);
      expect(d['quality']['reason'], 'invalid_score');
      expect(d['score'], isNull);
      expect(d['probabilities'], {'binaural_6': 1.0});
      expect(
        h.protocol.adaptation!.statistics.counts[StimulusAction.binaural6],
        0,
      );
      await h.stop();
    },
  );
  test(
    'valid stopped minutes retain reviewable statistics across a real SQLite process reopen',
    () async {
      final h = await AdaptiveHarness.open(durable: true);
      await h.advance(60);
      await h.stop();
      final saved = (await h.repository.listSessions()).single;
      expect(saved.status, 'stopped');
      final upload = (await h.repository.pendingUploads()).single;
      expect(await File(upload.payloadPath).exists(), true);
      await h.db.close();
      final reopened = AppDatabase(
        NativeDatabase(File('${h.dir.path}/state.sqlite')),
      );
      addTearDown(reopened.close);
      final stats = await MeditationActionRepository(
        reopened,
        SessionRepository(reopened),
      ).load(owner, h.scope, h.model);
      final own = stats.contributions
          .where((c) => c['kind'] == 'adaptive')
          .single;
      expect(own['session_id'], saved.id);
      expect(own['checksum_sha256'], saved.checksum);
      expect(stats.counts[StimulusAction.binaural6], 1);
      expect(
        () => MeditationActionStatistics.seeded(
          '99999999-9999-4999-8999-999999999999',
          h.scope,
          h.model,
        ),
        throwsArgumentError,
      );
      final simulatorScope = MeditationSetupContext(
        profile: h.scope.profile,
        eyeState: h.scope.eyeState,
        origin: DataOrigin.simulator,
      );
      final simulatorModel = PersonalEegModel.fromJson({
        ...h.model.toJson(),
        'origin': 'simulator',
      });
      expect(
        (await MeditationActionRepository(
          reopened,
          SessionRepository(reopened),
        ).load(owner, simulatorScope, simulatorModel)).counts[StimulusAction
            .binaural6],
        0,
      );
    },
  );
  for (final advantage in [6.49, 6.5, 6.51]) {
    test(
      'hysteresis requires .5 points after observing the current minute ($advantage)',
      () async {
        final h = await AdaptiveHarness.open(alternative: advantage);
        await h.advance(60);
        expect(
          h.protocol.currentAction,
          advantage < 6.5
              ? StimulusAction.binaural6
              : StimulusAction.binaural12,
        );
        final d = h.protocol.adaptation!.decisions.single;
        expect((d['probabilities'] as Map).length, 5);
        expect(
          (d['probabilities'] as Map).values.fold<double>(
            0,
            (a, b) => a + (b as num),
          ),
          closeTo(1, 1e-12),
        );
        expect(
          h.protocol.adaptation!.statistics.counts[StimulusAction.binaural6],
          1,
        );
        await h.stop();
      },
    );
  }
  for (var index = 0; index < 5; index++) {
    test(
      'uniform exploration can select action $index including current and unknown arms',
      () async {
        final values = [.05, (index + .1) / 5];
        var n = 0;
        final h = await AdaptiveHarness.open(random: () => values[n++]);
        await h.advance(60);
        expect(h.protocol.currentAction, fixedActionOrder[index]);
        final d = h.protocol.adaptation!.decisions.single;
        expect(d['reason'], 'exploration');
        expect(d['selection_probability'], index == 4 ? .92 : .02);
        expect(
          h.protocol.adaptation!.statistics.means.containsKey(
            StimulusAction.control,
          ),
          false,
        );
        await h.stop();
      },
    );
  }
  test(
    'missing or rejected EEG holds action without learning or random selection',
    () async {
      final h = await AdaptiveHarness.open(
        random: () => throw StateError('No selection for bad EEG'),
      );
      await h.advance(60, eeg: false);
      await h.advance(60, bad: true);
      expect(h.protocol.currentAction, StimulusAction.binaural6);
      expect(
        h.protocol.adaptation!.statistics.counts[StimulusAction.binaural6],
        0,
      );
      for (final d in h.protocol.adaptation!.decisions) {
        expect(d['score'], isNull);
        expect(d['updated_statistics'], false);
        expect(d['probabilities'], {'binaural_6': 1.0});
      }
      expect(h.audio.playing, true);
      await h.stop();
    },
  );
  test(
    'validated model with no observed seeds adapts directly; unsupported context stays preferred fixed',
    () async {
      final h = await AdaptiveHarness.open(noSeeds: true);
      expect(h.protocol.adaptation, isNotNull);
      await h.advance(60);
      expect(
        h.protocol.adaptation!.statistics.counts[StimulusAction.binaural6],
        1,
      );
      await h.stop();
      final fixed = await AdaptiveHarness.open(eyes: EyeState.open);
      expect(fixed.protocol.adaptation, isNull);
      expect(fixed.protocol.currentAction, StimulusAction.binaural6);
      await fixed.stop();
    },
  );
  test(
    '600 played seconds scores all ten minutes once and persists no future action with frozen model',
    () async {
      final h = await AdaptiveHarness.open();
      await h.advance(60);
      // Changing the persisted latest artifact cannot alter a session snapshot.
      await h.db.putKv(
        'meditation_model:v1:$owner:muse:meditation-1',
        jsonEncode({
          ...h.model.toJson(),
          'model_version': 'new',
          'intercept': 9,
        }),
      );
      await h.advance(540);
      await h.session.finish();
      await h.session.finish();
      final saved = (await h.repository.listSessions()).single;
      expect(saved.status, 'completed');
      expect(saved.manifest.durationSeconds, 600);
      expect(saved.manifest.meditation!['model_version'], 'v1');
      final decisions =
          saved.manifest.meditation!['adaptive_decisions'] as List;
      expect(decisions.length, 10);
      expect(decisions.map((d) => d['minute']).toSet().length, 10);
      expect(
        decisions.every(
          (d) => d['model_version'] == 'v1' && d['updated_statistics'] == true,
        ),
        true,
      );
      expect(decisions.last['selected_action'], isNull);
      expect(decisions.last['transition_start_frame'], isNull);
      expect(decisions.last['probabilities'], isEmpty);
      expect(h.audio.accepted, 600 * 48000);
      final restored = await h.actions.load(owner, h.scope, h.model);
      final own = restored.contributions
          .where((c) => c['kind'] == 'adaptive')
          .toList();
      expect(own.length, 10);
      expect(
        own.every(
          (c) =>
              c['session_id'] == saved.id &&
              c['checksum_sha256'] == saved.checksum,
        ),
        true,
      );
      expect(
        saved.frames
            .where((f) => f.playbackActive == true)
            .every(
              (f) =>
                  f.timeSeconds == f.activeTimeSeconds ||
                  (f.timeSeconds - f.activeTimeSeconds!).abs() < 1e-6,
            ),
        true,
      );
      expect(await h.repository.loadBandit('muse'), isNull);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
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
      expect(
        await repository.save(stats, isCurrent: () => true),
        false,
        reason: 'Unreviewable adaptive observation cannot be published',
      );
      expect(
        await repository.save(
          MeditationActionStatistics.seeded(owner, setup, model),
          isCurrent: () => true,
        ),
        true,
      );
      await sessions.bumpEvidenceEpoch(
        owner,
      ); // Freshness is not cached usability.
      final restored = await MeditationActionRepository(
        db,
        sessions,
      ).load(owner, setup, model);
      expect(restored.counts[StimulusAction.binaural6], 0);
      expect(restored.means.containsKey(StimulusAction.binaural6), false);
      expect(
        restored.includedSessionIds,
        containsAll(model.includedSessionIds),
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

class AdaptiveHarness {
  AdaptiveHarness(
    this.session,
    this.audio,
    this.repository,
    this.actions,
    this.scope,
    this.model,
    this.dir,
    this.db,
  );
  final SessionController session;
  final PlaybackAudio audio;
  final SessionRepository repository;
  final MeditationActionRepository actions;
  final MeditationSetupContext scope;
  final PersonalEegModel model;
  final Directory dir;
  final AppDatabase db;
  double observed = 0;
  int base = 0;
  int nextSourceSecond = 1;
  MeditationProtocol get protocol => session.engine! as MeditationProtocol;
  static Future<AdaptiveHarness> open({
    double alternative = 6.5,
    double Function()? random,
    EyeState eyes = EyeState.closed,
    bool noSeeds = false,
    bool durable = false,
    PlaybackAudio? output,
    PersonalEegModel Function(PersonalEegModel)? transformModel,
  }) async {
    final dir = await Directory.systemTemp.createTemp('adaptive-harness');
    final db = AppDatabase(
      durable
          ? NativeDatabase(File('${dir.path}/state.sqlite'))
          : NativeDatabase.memory(),
    );
    addTearDown(db.close);
    addTearDown(() => dir.delete(recursive: true));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => dir.path,
        );
    final bytes = wave(),
        profile = AudioProfileVersion.fromJson(metadata(wave()));
    final file = await File('${dir.path}/sound.wav').writeAsBytes(bytes);
    final audio = output ?? ClockedPlaybackAudio();
    final repository = SessionRepository(db),
        actions = MeditationActionRepository(db, SessionRepository(db));
    final scope = MeditationSetupContext(
      profile: profile,
      eyeState: eyes,
      origin: DataOrigin.muse,
    );
    var model = modelFor(profile, alternative: alternative);
    if (noSeeds) {
      model = PersonalEegModel.fromJson({
        ...model.toJson(),
        'fixed_minutes': [],
      });
    }
    model = transformModel?.call(model) ?? model;
    final stats = await actions.load(owner, scope, model);
    final config = ExperimentConfig.defaults();
    late AdaptiveHarness harness;
    final session = SessionController(
      repository: repository,
      ownerEmail: 'owner@test',
      audio: audio,
      keepAlive: KeepAlive(),
      config: config,
      snapshot: BanditSnapshot.empty(
        experimentVersion: config.version,
        origin: DataOrigin.muse,
      ),
      mode: SessionMode.personal,
      eyeState: eyes,
      origin: DataOrigin.muse,
      observedTimeSeconds: () => harness.observed,
      randomUnit: random ?? () => .9,
      meditation: MeditationSetup(
        profile: profile,
        file: file,
        action: StimulusAction.binaural6,
        model: model,
        statistics: stats,
        saveStatistics: (s) async {
          await actions.save(s, isCurrent: () => true);
        },
        metadata: {'owner_account_id': owner},
      ),
    );
    harness = AdaptiveHarness(
      session,
      audio,
      repository,
      actions,
      scope,
      model,
      dir,
      db,
    );
    addTearDown(session.dispose);
    expect(await session.start(muse: SilentMuse()), true);
    await session.pumpPlayback();
    harness.protocol.sourceAnchor(0, 0);
    return harness;
  }

  Future<void> advance(
    double seconds, {
    bool eeg = true,
    bool bad = false,
    double theta = 1.0,
  }) async {
    final target = session.activePlaybackFrames + (seconds * 48000).round();
    while (session.activePlaybackFrames < target) {
      await session.pumpPlayback();
      final frames = (target - session.activePlaybackFrames).clamp(1, 7200);
      observed += frames / 48000;
      audio.played = session.activePlaybackFrames - base + frames;
      while (nextSourceSecond <= observed + 1e-9) {
        if (eeg) {
          final raw = liveFrame(nextSourceSecond.toDouble(), theta: theta);
          protocol.queueFrame(
            bad
                ? FeatureFrame.fromJson({
                    ...raw.toJson(),
                    'rejected': true,
                    'reasons': ['poor_contact'],
                  })
                : raw,
          );
        }
        nextSourceSecond++;
      }
      await session.pumpPlayback();
    }
  }

  Future<void> stop() async {
    session.interrupt(StopReason.background);
    await session.finish();
  }
}
