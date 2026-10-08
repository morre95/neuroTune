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
import 'package:neurotune/data/database.dart';
import 'package:neurotune/data/repository.dart';
import 'package:neurotune/data/calibration_repository.dart';
import 'package:neurotune_core/neurotune_core.dart';
import 'package:neurotune/main.dart';
import 'package:neurotune/platform/channels.dart';
import 'profile_library_test.dart' show wave, metadata, owner, version;
import 'meditation_session_test.dart' show PlaybackAudio, KeepAlive;
import 'calibration_session_test.dart' show runAttempt, runFixedAttempt;

void main() {
  testWidgets(
    'offline calibration creates a locked series and blinds stopped attempts in live history and playback',
    (tester) async {
      var requests = 0;
      final (dir, db, api, audio, service) = (await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('meditation-offline');
        final db = AppDatabase(NativeDatabase.memory());
        final bytes = wave();
        final folder = await Directory(
          '${dir.path}/audio_profiles/$owner',
        ).create(recursive: true);
        final file = await File(
          '${folder.path}/$version.wav',
        ).writeAsBytes(bytes);
        await db
            .into(db.cachedAudioProfiles)
            .insert(
              CachedAudioProfilesCompanion.insert(
                ownerAccountId: owner,
                versionId: version,
                metadataJson: jsonEncode(metadata(bytes)),
                readyPath: Value(file.path),
              ),
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
        final api = ApiClient(
          baseUrl: 'http://offline',
          httpClient: MockClient((_) async {
            requests++;
            throw const SocketException('No network');
          }),
        );
        final audio = PlaybackAudio();
        final service = KeepAlive();
        return (dir, db, api, audio, service);
      }))!;
      await tester.pumpWidget(
        NeuroTuneApp(
          database: db,
          authStore: AuthStore(),
          api: api,
          audio: audio,
          keepAlive: service,
          muse: MuseChannel(),
          meditationEnabled: true,
        ),
      );
      for (
        var i = 0;
        i < 25 && find.text('Meditation').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(find.text('Meditation'), findsOneWidget);
      expect(requests, 0);
      await tester.scrollUntilVisible(find.text('Kalibrering'), 200);
      await tester.pump();
      await tester.tap(find.text('Kalibrering'));
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      await tester.tap(find.text('Ny serie · Simulator'));
      await tester.pump();
      for (
        var i = 0;
        i < 20 && find.text('Starta kalibrering').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      final calibration = CalibrationRepository(db, SessionRepository(db));
      final plans = (await tester.runAsync(() => calibration.plans(owner)))!;
      expect(plans, hasLength(1));
      expect(plans.single.origin, DataOrigin.simulator);
      await tester.ensureVisible(find.text('Starta kalibrering'));
      await tester.tap(find.text('Starta kalibrering'));
      for (
        var i = 0;
        i < 30 && find.textContaining('Aktiv tid').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      final requestsDuringPlayback = requests;
      await tester.pump(const Duration(seconds: 1));
      expect(requests, requestsDuringPlayback);
      expect(service.active, true);
      expect(find.text('Åtgärd: Dold till seriens slut'), findsOneWidget);
      expect(find.textContaining(' Hz'), findsNothing);
      expect(
        (await tester.runAsync(
          () => calibration.progress(owner, plans.single.id),
        ))!.attempts,
        hasLength(1),
      );
      await tester.ensureVisible(find.text('Avsluta session'));
      await tester.tap(find.text('Avsluta session'));
      for (
        var i = 0;
        i < 30 && find.text('Kalibrering').evaluate().isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(
        (await tester.runAsync(
          () => calibration.progress(owner, plans.single.id),
        ))!.completedSlots,
        0,
      );
      expect(find.textContaining('0/10'), findsOneWidget);
      expect(find.textContaining(' Hz'), findsNothing);
      await tester.ensureVisible(find.text('Tillbaka'));
      await tester.tap(find.text('Tillbaka'));
      await tester.pump();
      await tester.ensureVisible(find.text('Sessionshistorik'));
      await tester.tap(find.text('Sessionshistorik'));
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      expect(find.textContaining('Dold till seriens slut'), findsOneWidget);
      await tester.tap(find.byType(ListTile).first);
      await tester.pump();
      expect(find.text('Åtgärd: Dold till seriens slut'), findsOneWidget);
      expect(find.textContaining(' Hz'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.runAsync(() => dir.delete(recursive: true));
    },
  );
  for (final fixed in [false, true]) {
    testWidgets(
      fixed
          ? 'fixed-session partial feedback is recoverable in the primary app offline'
          : 'saved partial feedback is recoverable in the primary app and shows post-session endpoints offline',
      (tester) async {
        final syncRequests = <String>[];
        final (dir, db, api, audio, service) = (await tester.runAsync(() async {
          final dir = await Directory.systemTemp.createTemp(
            'meditation-offline',
          );
          final db = AppDatabase(NativeDatabase.memory());
          final bytes = wave();
          final folder = await Directory(
            '${dir.path}/audio_profiles/$owner',
          ).create(recursive: true);
          final file = await File(
            '${folder.path}/$version.wav',
          ).writeAsBytes(bytes);
          await db
              .into(db.cachedAudioProfiles)
              .insert(
                CachedAudioProfilesCompanion.insert(
                  ownerAccountId: owner,
                  versionId: version,
                  metadataJson: jsonEncode(metadata(bytes)),
                  readyPath: Value(file.path),
                ),
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
          final api = ApiClient(
            baseUrl: 'http://offline',
            httpClient: MockClient((request) async {
              syncRequests.add(request.url.path);
              throw const SocketException('No network');
            }),
          );
          final audio = PlaybackAudio();
          final service = KeepAlive();
          return (dir, db, api, audio, service);
        }))!;
        final calibration = CalibrationRepository(db, SessionRepository(db));
        final plan = await tester.runAsync(() async {
          if (fixed) {
            await runFixedAttempt(
              SessionRepository(db),
              AudioProfileVersion.fromJson(metadata(wave())),
              File('${dir.path}/audio_profiles/$owner/$version.wav'),
              'delayed-ui',
            );
            await calibration.saveFeedback(
              owner,
              'delayed-ui',
              mentalBusyness: 3,
            );
            return null;
          }
          final plan = await calibration.createPlan(
            ownerAccountId: owner,
            profile: AudioProfileVersion.fromJson(metadata(wave())),
            eyeState: EyeState.closed,
            origin: DataOrigin.muse,
          );
          await runAttempt(
            calibration,
            SessionRepository(db),
            plan,
            File('${dir.path}/audio_profiles/$owner/$version.wav'),
            'delayed-ui',
          );
          await calibration.saveFeedback(
            owner,
            'delayed-ui',
            mentalBusyness: 3,
          );
          return plan;
        });
        await tester.pumpWidget(
          NeuroTuneApp(
            database: db,
            authStore: AuthStore(),
            api: api,
            audio: audio,
            keepAlive: service,
            muse: MuseChannel(),
            meditationEnabled: true,
          ),
        );
        for (
          var i = 0;
          i < 25 && find.text('Meditation').evaluate().isEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        expect(find.text('Meditation'), findsOneWidget);
        expect(syncRequests, everyElement('/v1/meditation/calibration-plans'));
        if (fixed) expect(syncRequests, isEmpty);
        await tester.scrollUntilVisible(find.text('Kalibrering'), 200);
        await tester.pump();
        await tester.tap(find.text('Kalibrering'));
        await tester.pump();
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        expect(find.text('Slutför återkoppling'), findsOneWidget);
        await tester.ensureVisible(find.text('Slutför återkoppling'));
        await tester.tap(find.text('Slutför återkoppling'));
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        expect(find.text('Efter meditationen'), findsOneWidget);
        expect(find.text('Mental upptagenhet'), findsOneWidget);
        expect(find.text('Avslappning'), findsOneWidget);
        expect(find.text('0 · ingen — 10 · extrem'), findsOneWidget);
        expect(find.text('0 · ingen — 10 · fullständig'), findsOneWidget);
        expect(find.text('3 / 10'), findsOneWidget);
        expect(find.textContaining(' Hz'), findsNothing);
        expect(service.active, false);
        await tester.ensureVisible(find.widgetWithText(ChoiceChip, '8').last);
        await tester.tap(find.widgetWithText(ChoiceChip, '8').last);
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        expect(
          (await tester.runAsync(
            () => calibration.feedback(owner, 'delayed-ui'),
          ))!.relaxation,
          8,
        );
        await tester.ensureVisible(find.text('Klar'));
        await tester.tap(find.text('Klar'));
        for (var i = 0; i < 10; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        if (fixed) {
          expect(
            (await tester.runAsync(() => calibration.plans(owner)))!,
            isEmpty,
          );
          expect(
            (await tester.runAsync(
              () => calibration.feedback(owner, 'delayed-ui'),
            ))!.complete,
            true,
          );
        } else {
          expect(find.textContaining('1/10'), findsOneWidget);
          expect(
            (await tester.runAsync(
              () => calibration.progress(owner, plan!.id),
            ))!.completedSlots,
            1,
          );
        }
        expect(find.text('Slutför återkoppling'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.runAsync(() => dir.delete(recursive: true));
      },
    );
  }
}
