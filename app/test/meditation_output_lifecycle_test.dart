import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:neurotune/data/database.dart';
import 'package:neurotune/data/repository.dart';
import 'package:neurotune/session/session_controller.dart';
import 'package:neurotune_core/neurotune_core.dart';
import 'profile_library_test.dart' show wave, metadata;
import 'meditation_session_test.dart' show PlaybackAudio, KeepAlive, SilentMuse;

class RateAudio extends PlaybackAudio {
  int? startedRate;
  int stops = 0;
  bool failFinalStop = false;
  @override
  Future<double?> start(int rate) async {
    startedRate = rate;
    return super.start(rate);
  }

  @override
  Future<void> stop() async {
    stops++;
    if (failFinalStop && stops == 3) throw StateError('Native stop failed');
    return super.stop();
  }
}

class RecordingMuse extends SilentMuse {
  bool stopped = false;
  @override
  Future<void> stop() async {
    stopped = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final scenario in ['meditation-rate', 'nir-rate', 'cleanup']) {
    final badRate = scenario != 'cleanup';
    final meditation = scenario != 'nir-rate';
    test(
      scenario == 'nir-rate'
          ? 'NIR output retains its independently configured rate'
          : badRate
          ? 'meditation audio ignores independently configurable NIR rate'
          : 'a cleanup stop error still releases the foreground service',
      () async {
        final dir = await Directory.systemTemp.createTemp('meditation-review');
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        addTearDown(() => dir.delete(recursive: true));
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              (_) async => dir.path,
            );
        final bytes = wave();
        final file = await File('${dir.path}/ready.wav').writeAsBytes(bytes);
        final json = ExperimentConfig.defaults().toJson();
        if (badRate) json['audio_sample_rate_hz'] = 44100;
        final config = ExperimentConfig.fromJson(json);
        final audio = RateAudio();
        final service = KeepAlive();
        final session = SessionController(
          repository: SessionRepository(db),
          ownerEmail: 'owner@test',
          audio: audio,
          keepAlive: service,
          config: config,
          snapshot: BanditSnapshot.empty(
            experimentVersion: config.version,
            origin: DataOrigin.muse,
          ),
          mode: SessionMode.comparison,
          eyeState: EyeState.closed,
          origin: DataOrigin.muse,
          meditation: meditation
              ? MeditationSetup(
                  profile: AudioProfileVersion.fromJson(metadata(bytes)),
                  file: file,
                  action: StimulusAction.control,
                )
              : null,
        );
        addTearDown(session.dispose);
        final muse = RecordingMuse();
        expect(await session.start(muse: muse), true);
        if (badRate) {
          expect(audio.startedRate, meditation ? 48000 : 44100);
          await session.finish();
        } else {
          audio.failFinalStop = true;
          await expectLater(session.finish(), throwsStateError);
          expect(
            service.active,
            false,
            reason:
                'All resources must be released even when native stop throws',
          );
          expect(muse.stopped, true);
          expect(session.saved, true);
          expect(
            (await session.repository.listSessions()).single.status,
            'stopped',
          );
        }
      },
    );
  }
}
