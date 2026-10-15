import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurotune/data/database.dart';
import 'package:neurotune/data/repository.dart';
import 'package:neurotune/session/session_controller.dart';
import 'package:neurotune_core/neurotune_core.dart';

import 'meditation_session_test.dart'
    show ClockedPlaybackAudio, KeepAlive, StreamMuse, PlaybackAudio;
import 'profile_library_test.dart' show metadata, wave;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'direct legacy controller keeps only matching current-source statistics',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final legacy = ExperimentConfig.fromJson({
        ...ExperimentConfig.defaults().toJson(),
        'version': '2026.3',
        'quality_version': '2026.3-unverified',
        'notch_q': 21.0,
      });
      for (final (version, origin) in [
        ('2026.3', DataOrigin.simulator),
        ('2026.4', DataOrigin.muse),
        ('2026.4', DataOrigin.simulator),
      ]) {
        final snapshot = BanditSnapshot(
          policyVersion: 'retained',
          experimentVersion: version,
          dataOrigin: origin.name,
          epsilon: .2,
          actions: {
            for (final action in StimulusAction.values)
              action: const ActionStat(12, .5),
          },
          includedSessionIds: const ['history'],
          createdAtIso: '2026-10-09T00:00:00Z',
        );
        final controller = SessionController(
          repository: SessionRepository(db),
          ownerEmail: 'owner@test',
          audio: PlaybackAudio(),
          keepAlive: KeepAlive(),
          config: legacy,
          snapshot: snapshot,
          mode: SessionMode.personal,
          eyeState: EyeState.closed,
          origin: DataOrigin.simulator,
        );
        expect(controller.config.version, '2026.4');
        expect(controller.config.qualityVersion, '2026.4-unverified');
        expect(controller.config.notchQ, 21);
        expect(controller.snapshot.experimentVersion, '2026.4');
        expect(controller.snapshot.dataOrigin, 'simulator');
        expect(
          controller.snapshot.actions[StimulusAction.control]!.n,
          version == '2026.4' && origin == DataOrigin.simulator ? 12 : 0,
        );
        controller.dispose();
      }
      expect(legacy.version, '2026.3');
      expect(legacy.qualityVersion, '2026.3-unverified');
      final unknown = ExperimentConfig.fromJson({
        ...legacy.toJson(),
        'version': 'future',
        'quality_version': 'future-quality',
      });
      expect(unknown.forCurrentProcessing().toJson(), unknown.toJson());
      final current = ExperimentConfig.defaults();
      expect(current.forCurrentProcessing().toJson(), current.toJson());
    },
  );
  test(
    'offline legacy config records current EEG quality without relabeling history or raw',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'meditation-eeg-quality',
      );
      addTearDown(() => dir.delete(recursive: true));
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => dir.path,
          );
      final bytes = wave();
      final file = await File('${dir.path}/ready.wav').writeAsBytes(bytes);
      final repository = SessionRepository(db);
      final legacy = ExperimentConfig.fromJson({
        ...ExperimentConfig.defaults().toJson(),
        'version': '2026.3',
        'quality_version': '2026.3-unverified',
        'notch_q': 21.0,
      });
      await repository.saveConfig(legacy);
      final historical = MeditationProtocol(
        context: SessionContext(
          sessionId: 'legacy-history',
          origin: DataOrigin.muse,
          eyeState: EyeState.closed,
          sampleRateHz: 256,
          channelNames: const ['EEG1', 'EEG2', 'EEG3', 'EEG4'],
          seed: 1,
          startedAt: DateTime.utc(2026),
        ),
        profile: AudioProfileVersion.fromJson(metadata(bytes)),
        action: StimulusAction.control,
        metadata: {
          'quality_version': legacy.qualityVersion,
          'eeg_config': legacy.toJson(),
        },
      );
      final historicalRaw = utf8.encode('{}'),
          historicalChecksum = sha256Hex(utf8.encode('{}'));
      await repository.saveSession(
        manifest: historical.manifest(checksum: historicalChecksum),
        decisions: [],
        frames: [],
        raw: historicalRaw,
        checksum: historicalChecksum,
        status: 'stopped',
      );
      final config = await repository.loadConfig();
      final audio = ClockedPlaybackAudio(), muse = StreamMuse();
      addTearDown(muse.close);
      var observed = 0.0, lastObserved = -0.000001;
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
        mode: SessionMode.comparison,
        eyeState: EyeState.closed,
        origin: DataOrigin.muse,
        observedTimeSeconds: () {
          lastObserved = observed > lastObserved
              ? observed
              : lastObserved + .000001;
          return lastObserved;
        },
        meditation: MeditationSetup(
          profile: AudioProfileVersion.fromJson(metadata(bytes)),
          file: file,
          action: StimulusAction.control,
        ),
      );
      addTearDown(session.dispose);
      expect(await session.start(muse: muse), isTrue);
      for (var step = 1; step <= 64; step++) {
        await session.pumpPlayback();
        observed = step * .125;
        audio.played = (observed * 48000).round();
        await session.pumpPlayback();
        if (step % 4 == 0) {
          final start = observed - .5;
          // Entirely synthetic uV input, including a preserved 1000uV reference.
          final signal = [
            for (var i = 0; i < 128; i++)
              1000 + (5 * sin(2 * pi * 4 * (start + i / 256)) * 8).round() / 8,
          ];
          muse.eegOut.add(
            EegBatch(
              channelNames: const ['EEG1', 'EEG2', 'EEG3', 'EEG4'],
              unit: 'uV',
              sampleRateHz: 256,
              timeSeconds: 300 + start,
              eeg: [signal, signal, signal, signal],
              contact: [
                for (var i = 0; i < 128; i++) [1, 1, 1, 1],
              ],
              accel: [
                for (var i = 0; i < 128; i++) [0, 0, 1],
              ],
              gyro: [
                for (var i = 0; i < 128; i++) [0, 0, 0],
              ],
            ),
          );
          await Future<void>.delayed(Duration.zero);
        }
      }
      for (var i = 0; i < 100 && session.engine!.frames.length < 5; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(session.view.quality, '4/4 kanaler');
      session.interrupt(StopReason.background);
      await session.finish();
      final history = await session.repository.listSessions();
      final saved = history.singleWhere((s) => s.id != 'legacy-history');
      expect(saved.frames, hasLength(5));
      expect(
        saved.frames.every((frame) => frame.channels.every((c) => c.valid)),
        isTrue,
      );
      expect(
        saved.manifest.meditation!['quality_version'],
        '2026.4-unverified',
      );
      expect(saved.manifest.meditation!['eeg_config']['version'], '2026.4');
      expect(saved.manifest.meditation!['eeg_config']['notch_q'], 21.0);
      final retained = history.singleWhere((s) => s.id == 'legacy-history');
      expect(
        retained.manifest.meditation!['quality_version'],
        '2026.3-unverified',
      );
      expect(retained.manifest.meditation!['eeg_config']['version'], '2026.3');
      final upload = (await session.repository.pendingUploads()).single;
      final raw =
          jsonDecode(await File(upload.payloadPath).readAsString()) as Map;
      expect(raw['eeg'][0]['eeg'][0][0], 1000);
      expect(raw['eeg'][0]['unit'], 'uV');
    },
  );
}
