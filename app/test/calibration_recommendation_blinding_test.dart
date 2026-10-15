import 'dart:convert';
import 'dart:io';
import 'dart:math';
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
import 'package:neurotune/ui/session_page.dart' show actionLabel;
import 'package:neurotune_core/neurotune_core.dart';
import 'meditation_session_test.dart' show PlaybackAudio, KeepAlive;
import 'profile_library_test.dart' show owner, metadata, wave;
import 'recommendation_repository_test.dart' show restoreSeries;
import 'recommendation_ui_test.dart' show settleIo;

void main() {
  for (final completedSeries in [false, true]) {
    testWidgets(
      completedSeries
          ? 'fixed playback and visible means use completed evidence while a new exact series stays blinded'
          : 'fixed playback uses control while the first series remains blinded',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 3200);
        addTearDown(tester.view.reset);
        final (dir, db, expected) = (await tester.runAsync(() async {
          final dir = await Directory.systemTemp.createTemp(
            'calibration-blinding',
          );
          final db = AppDatabase(
            NativeDatabase(File('${dir.path}/state.sqlite')),
          );
          final bytes = wave();
          final original = AudioProfileVersion.fromJson(metadata(bytes));
          final pending = AudioProfileVersion.fromJson({
            ...metadata(
              bytes,
              id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
              number: 2,
            ),
            'name': 'Pending setup',
            'carrier_hz': 300,
          });
          final folder = await Directory(
            '${dir.path}/audio_profiles/$owner',
          ).create(recursive: true);
          for (final profile in [original, pending]) {
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
          }
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
          final partial = await restoreSeries(
            calibration,
            sessions,
            pending,
            DataOrigin.simulator,
            (_) => (0, 10),
            slots: 1,
            random: Random(42),
          );
          expect(partial.schedule.first, isNot(StimulusAction.control));
          final preferred = partial.schedule.first == StimulusAction.binaural12
              ? StimulusAction.binaural6
              : StimulusAction.binaural12;
          if (completedSeries) {
            await restoreSeries(
              calibration,
              sessions,
              original,
              DataOrigin.simulator,
              (action) => action == preferred ? (0, 10) : (10, 0),
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
          return (
            dir,
            db,
            completedSeries ? preferred : StimulusAction.control,
          );
        }))!;
        await tester.pumpWidget(
          NeuroTuneApp(
            database: db,
            authStore: AuthStore(),
            api: ApiClient(
              baseUrl: 'http://offline',
              httpClient: MockClient((_) async {
                throw const SocketException('offline');
              }),
            ),
            audio: PlaybackAudio(),
            keepAlive: KeepAlive(),
            muse: MuseChannel(),
            meditationEnabled: true,
          ),
        );
        await settleIo(tester);
        expect(find.text('Meditation'), findsOneWidget);
        if (completedSeries) {
          await tester.scrollUntilVisible(find.text('Kalibrering'), 200);
          await tester.tap(find.text('Kalibrering'));
          await settleIo(tester);
          await tester.tap(find.text('Fast ton för vald profil · simulator'));
          await settleIo(tester);
          expect(
            find.text('Rekommenderad: ${actionLabel(expected.id)}'),
            findsOneWidget,
          );
          expect(
            find.textContaining(
              '10 fullständigt skattade kalibreringssessioner',
            ),
            findsOneWidget,
          );
          expect(
            find.textContaining('medel 10.0 · 2 sessioner'),
            findsOneWidget,
          );
          await tester.scrollUntilVisible(find.text('Tillbaka'), 200);
          await tester.tap(find.text('Tillbaka'));
          await tester.pump();
          await tester.scrollUntilVisible(find.text('Tillbaka'), 200);
          await tester.tap(find.text('Tillbaka'));
          await tester.pump();
        }
        await tester.scrollUntilVisible(find.text('Simulator'), -200);
        await tester.tap(find.text('Simulator'));
        await tester.pump();
        await tester.tap(find.text('Starta meditation'));
        await settleIo(tester);
        expect(
          find.text('Åtgärd: ${actionLabel(expected.id)}'),
          findsOneWidget,
        );
        await tester.tap(find.text('Stoppa'));
        await settleIo(tester);
        await tester.tap(find.text('Avsluta session'));
        await settleIo(tester);
        final saved = (await tester.runAsync(
          () => SessionRepository(db).listSessions(),
        ))!;
        expect(
          saved
              .singleWhere((s) => s.manifest.meditation?['mode'] == 'fixed')
              .manifest
              .meditation!['fixed_action'],
          expected.id,
        );
        await tester.pumpWidget(const SizedBox());
        await settleIo(tester, 5);
        await tester.runAsync(() => dir.delete(recursive: true));
      },
    );
  }
}
