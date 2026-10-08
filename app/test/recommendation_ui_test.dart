import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide KeepAlive;
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:neurotune/data/api_client.dart';
import 'package:neurotune/data/auth_store.dart';
import 'package:neurotune/data/calibration_repository.dart';
import 'package:neurotune/data/database.dart';
import 'package:neurotune/data/repository.dart';
import 'package:neurotune/main.dart';
import 'package:neurotune/platform/channels.dart';
import 'package:neurotune_core/neurotune_core.dart';
import 'meditation_session_test.dart' show PlaybackAudio, KeepAlive;
import 'profile_library_test.dart' show owner, metadata, wave;
import 'recommendation_repository_test.dart' show restoreSeries;

Future<void> settleIo(WidgetTester tester, [int cycles = 15]) async {
  for (var n = 0; n < cycles; n++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

void main() {
  testWidgets(
    'offline results preference restart and a full fixed meditation use the chosen action',
    (tester) async {
      final (dir, file, db, plan) = (await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('preference-ui');
        final file = File('${dir.path}/state.sqlite');
        final db = AppDatabase(NativeDatabase(file));
        final bytes = wave();
        final profile = AudioProfileVersion.fromJson(metadata(bytes));
        final folder = await Directory(
          '${dir.path}/audio_profiles/$owner',
        ).create(recursive: true);
        final local = await File(
          '${folder.path}/${profile.id}.wav',
        ).writeAsBytes(bytes);
        await db
            .into(db.cachedAudioProfiles)
            .insert(
              CachedAudioProfilesCompanion.insert(
                ownerAccountId: owner,
                versionId: profile.id,
                metadataJson: jsonEncode(profile.toJson()),
                readyPath: Value(local.path),
              ),
            );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              (_) async => dir.path,
            );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('dev.neurotune/audio'),
              (_) async => null,
            );
        final sessions = SessionRepository(db);
        final calibration = CalibrationRepository(db, sessions);
        final plan = await restoreSeries(
          calibration,
          sessions,
          profile,
          DataOrigin.simulator,
          (_) => (4, 8),
        );
        final token =
            'header.${base64Url.encode(utf8.encode(jsonEncode({'sub': owner})))}.signature';
        FlutterSecureStorage.setMockInitialValues({
          'auth': jsonEncode(
            AuthTokens(
              accessToken: token,
              refreshToken: 'refresh',
              email: 'owner@test',
            ).toJson(),
          ),
        });
        return (dir, file, db, plan);
      }))!;
      var requests = 0;
      NeuroTuneApp app(AppDatabase database, PlaybackAudio audio) =>
          NeuroTuneApp(
            database: database,
            authStore: AuthStore(),
            api: ApiClient(
              baseUrl: 'http://offline',
              httpClient: MockClient((_) async {
                requests++;
                throw const SocketException('offline');
              }),
            ),
            audio: audio,
            keepAlive: KeepAlive(),
            muse: MuseChannel(),
            meditationEnabled: true,
          );
      await tester.pumpWidget(app(db, PlaybackAudio()));
      await settleIo(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, '6 Hz'));
      await tester.pump();
      await tester.scrollUntilVisible(find.text('Kalibrering'), 200);
      await tester.pump();
      await tester.tap(find.text('Kalibrering'));
      await settleIo(tester);
      expect(find.text('Resultat och fast ton'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Resultat och fast ton'), 200);
      await tester.pump();
      await tester.tap(find.text('Resultat och fast ton'));
      await settleIo(tester);
      expect(find.text('Rekommenderad: Kontroll'), findsOneWidget);
      await tester.scrollUntilVisible(find.textContaining('Session 1:'), 200);
      await tester.pump();
      expect(
        find.textContaining('Mental upptagenhet 4 · Avslappning 8 · Poäng 7.0'),
        findsWidgets,
      );
      await tester.scrollUntilVisible(
        find.widgetWithText(ChoiceChip, 'Binauralt 12 Hz'),
        -200,
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(ChoiceChip, 'Binauralt 12 Hz'));
      await settleIo(tester);
      await tester.scrollUntilVisible(
        find.text('Vald fast ton: Binauralt 12 Hz'),
        -200,
      );
      await tester.pump();
      expect(find.text('Vald fast ton: Binauralt 12 Hz'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Tillbaka'), 200);
      await tester.pump();
      await tester.tap(find.text('Tillbaka'));
      await tester.pump();
      await tester.scrollUntilVisible(find.text('Tillbaka'), 200);
      await tester.pump();
      await tester.tap(find.text('Tillbaka'));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.widgetWithText(ChoiceChip, '6 Hz'),
        -200,
      );
      await tester.pump();
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '6 Hz'))
            .selected,
        false,
        reason:
            'Saving a preference replaces the previous pending home override',
      );
      await tester.scrollUntilVisible(find.text('Kalibrering'), 200);
      await tester.pump();
      await tester.tap(find.text('Kalibrering'));
      await settleIo(tester);
      await tester.scrollUntilVisible(find.text('Resultat och fast ton'), 200);
      await tester.pump();
      await tester.tap(find.text('Resultat och fast ton'));
      await settleIo(tester);
      await tester.scrollUntilVisible(find.text('Samla en serie till'), 200);
      await tester.pump();
      await tester.tap(find.text('Samla en serie till'));
      await settleIo(tester);
      expect(find.text('Starta kalibrering'), findsOneWidget);
      final plans = (await tester.runAsync(
        () => CalibrationRepository(db, SessionRepository(db)).plans(owner),
      ))!;
      expect(plans.length, 2);
      final extra = plans.firstWhere((p) => p.id != plan.id);
      expect(extra.profile.id, plan.profile.id);
      expect(extra.eyeState, plan.eyeState);
      expect(extra.origin, plan.origin);
      for (final action in StimulusAction.values) {
        expect(extra.schedule.where((a) => a == action).length, 2);
      }
      await tester.pumpWidget(const SizedBox());
      await settleIo(tester, 5);
      final restarted = (await tester.runAsync(
        () async => AppDatabase(NativeDatabase(file)),
      ))!;
      final audio = PlaybackAudio();
      await tester.pumpWidget(app(restarted, audio));
      await settleIo(tester);
      expect(
        tester
            .widgetList<ChoiceChip>(find.byType(ChoiceChip))
            .where((chip) => chip.selected),
        isEmpty,
        reason:
            'An untouched selector must not claim a new override of the saved preference',
      );
      await tester.ensureVisible(find.text('Simulator'));
      await tester.pump();
      await tester.tap(find.text('Simulator'));
      await tester.pump();
      final beforeAudio = requests;
      await tester.tap(find.text('Starta meditation'));
      await settleIo(tester);
      for (
        var tick = 0;
        tick < 8000 && audio.played < MeditationProtocol.totalFrames;
        tick++
      ) {
        await tester.pump(const Duration(milliseconds: 50));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 2)),
        );
      }
      await tester.pump(const Duration(milliseconds: 50));
      await settleIo(tester);
      expect(audio.played, MeditationProtocol.totalFrames);
      expect(find.text('Åtgärd: Binauralt 12 Hz'), findsOneWidget);
      expect(
        requests,
        beforeAudio,
        reason: 'Preference resolution and active playback remain offline',
      );
      await tester.ensureVisible(find.text('Avsluta session'));
      await tester.pump();
      await tester.tap(find.text('Avsluta session'));
      await settleIo(tester);
      expect(find.text('Efter meditationen'), findsOneWidget);
      final saved = (await tester.runAsync(
        () => SessionRepository(restarted).listSessions(),
      ))!;
      final fixed = saved.singleWhere(
        (s) => s.manifest.meditation?['mode'] == 'fixed',
      );
      expect(fixed.manifest.meditation!['fixed_action'], 'binaural_12');
      expect(fixed.manifest.durationSeconds, 600);
      await tester.pumpWidget(const SizedBox());
      await settleIo(tester, 5);
      await tester.runAsync(() => dir.delete(recursive: true));
    },
  );
}
