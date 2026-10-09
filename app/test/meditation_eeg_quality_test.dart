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
    show ClockedPlaybackAudio, KeepAlive, StreamMuse;
import 'profile_library_test.dart' show metadata, wave;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'head-worn EEG with a stable reference stays valid and raw in the recording',
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
      final config = ExperimentConfig.defaults();
      final audio = ClockedPlaybackAudio(), muse = StreamMuse();
      addTearDown(muse.close);
      var observed = 0.0, lastObserved = -0.000001;
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
      final saved = (await session.repository.listSessions()).single;
      expect(saved.frames, hasLength(5));
      expect(
        saved.frames.every((frame) => frame.channels.every((c) => c.valid)),
        isTrue,
      );
      expect(
        saved.manifest.meditation!['quality_version'],
        '2026.4-unverified',
      );
      final upload = (await session.repository.pendingUploads()).single;
      final raw =
          jsonDecode(await File(upload.payloadPath).readAsString()) as Map;
      expect(raw['eeg'][0]['eeg'][0][0], 1000);
      expect(raw['eeg'][0]['unit'], 'uV');
    },
  );
}
