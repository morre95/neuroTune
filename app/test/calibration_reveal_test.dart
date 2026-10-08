import 'dart:convert';
import 'dart:io';
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
import 'package:neurotune/ui/session_page.dart';
import 'package:neurotune_core/neurotune_core.dart';
import 'meditation_session_test.dart' show PlaybackAudio, KeepAlive;
import 'profile_library_test.dart' show owner, metadata, wave;

void main() {
  testWidgets(
    'restored complete series reveals assignments in results history and playback',
    (tester) async {
      final (db, dir, plan) = (await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('calibration-reveal');
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
        final db = AppDatabase(NativeDatabase.memory());
        final sessions = SessionRepository(db);
        final calibration = CalibrationRepository(db, sessions);
        final plan = await calibration.createPlan(
          ownerAccountId: owner,
          profile: AudioProfileVersion.fromJson(metadata(wave())),
          eyeState: EyeState.closed,
          origin: DataOrigin.muse,
        );
        // Existing completed recordings are restored through the real persistence
        // interface; full played PCM and stopped behavior are tested by controllers.
        for (var slot = 0; slot < 10; slot++) {
          final id = 'restored-$slot';
          await calibration.reserveAttempt(owner, plan.id, id);
          final protocol = MeditationProtocol(
            context: SessionContext(
              sessionId: id,
              origin: plan.origin,
              eyeState: plan.eyeState,
              sampleRateHz: 256,
              channelNames: simulatorChannels,
              seed: 1,
              startedAt: DateTime.utc(2026, 1, slot + 1),
            ),
            profile: plan.profile,
            action: plan.schedule[slot],
            metadata: plan.sessionMetadata(slot),
          );
          protocol.playback(MeditationProtocol.totalFrames, 600);
          final raw = utf8.encode('{}');
          final digest = sha256Hex(raw);
          final path = await sessions.saveSession(
            manifest: protocol.manifest(checksum: digest),
            decisions: [],
            frames: [],
            raw: raw,
            checksum: digest,
            status: 'completed',
          );
          await sessions.enqueueUpload(id, digest, path, 'owner@test');
          await calibration.saveFeedback(
            owner,
            id,
            mentalBusyness: 4,
            relaxation: 6,
          );
        }
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
        return (db, dir, plan);
      }))!;
      await tester.pumpWidget(
        NeuroTuneApp(
          database: db,
          authStore: AuthStore(),
          api: ApiClient(
            baseUrl: 'http://offline',
            httpClient: MockClient(
              (_) async => throw const SocketException('offline'),
            ),
          ),
          audio: PlaybackAudio(),
          keepAlive: KeepAlive(),
          muse: MuseChannel(),
          meditationEnabled: true,
        ),
      );
      for (
        var n = 0;
        n < 25 && find.text('Meditation').evaluate().isEmpty;
        n++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(
        find.text('Meditation'),
        findsOneWidget,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .join(' | '),
      );
      await tester.scrollUntilVisible(find.text('Kalibrering'), 200);
      await tester.pump();
      await tester.tap(find.text('Kalibrering'));
      for (var n = 0; n < 15; n++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(find.textContaining('10/10'), findsOneWidget);
      await tester.scrollUntilVisible(find.textContaining('Session 10:'), 200);
      expect(
        find.text('Session 10: ${actionLabel(plan.schedule[9].id)}'),
        findsOneWidget,
      );
      expect(find.textContaining('Dold till seriens slut'), findsNothing);
      await tester.scrollUntilVisible(find.text('Tillbaka'), 200);
      await tester.tap(find.text('Tillbaka'));
      await tester.pump();
      await tester.ensureVisible(find.text('Sessionshistorik'));
      await tester.pump();
      await tester.tap(find.text('Sessionshistorik'));
      for (var n = 0; n < 15; n++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(find.textContaining('Dold till seriens slut'), findsNothing);
      await tester.tap(find.byType(ListTile).first);
      await tester.pump();
      expect(
        find.textContaining('Åtgärd: Binauralt').evaluate().isNotEmpty ||
            find.text('Åtgärd: Kontroll').evaluate().isNotEmpty,
        true,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.runAsync(() => dir.delete(recursive: true));
    },
  );
}
