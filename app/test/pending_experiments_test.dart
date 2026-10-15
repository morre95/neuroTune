import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
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
import 'package:neurotune_core/neurotune_core.dart';
import 'package:neurotune/main.dart';
import 'package:neurotune/platform/channels.dart';
import 'profile_library_test.dart' show wave, metadata, owner, version;
import 'meditation_session_test.dart' show PlaybackAudio, KeepAlive;

void main() {
  for (final obsolete in [true, false]) {
    testWidgets(
      obsolete
          ? 'meditation joins obsolete Experiments HTTP before playback and cancels policy follow-up'
          : 'Experiments remains usable and returns to cached meditation',
      (tester) async {
        var requests = 0;
        final heldExperiment = Completer<http.Response>();
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
              requests++;
              if (request.url.path == '/v1/experiments/active') {
                return heldExperiment.future;
              }
              if (!obsolete) {
                return http.Response(
                  jsonEncode(
                    BanditSnapshot.empty(
                      experimentVersion: ExperimentConfig.defaults().version,
                      origin: DataOrigin.simulator,
                    ).toJson(),
                  ),
                  200,
                );
              }
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
        await tester.scrollUntilVisible(find.text('Experiments'), 150);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Experiments'));
        await tester.pump();
        expect(requests, 1);
        if (!obsolete) {
          heldExperiment.complete(
            http.Response(
              jsonEncode(ExperimentConfig.defaults().toJson()),
              200,
            ),
          );
          for (
            var i = 0;
            i < 25 && find.text('Policy 0').evaluate().isEmpty;
            i++
          ) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump();
          }
          expect(find.text('Policy 0'), findsOneWidget);
          expect(requests, 2);
          await tester.tap(find.byIcon(Icons.arrow_back));
          await tester.pump();
          expect(find.text('Meditation'), findsOneWidget);
        }
        await tester.scrollUntilVisible(find.text('Simulator'), -150);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Simulator'));
        await tester.pump(const Duration(seconds: 1));
        await tester.ensureVisible(find.text('Starta meditation'));
        await tester.tap(find.text('Starta meditation'));
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
        if (obsolete) {
          expect(
            service.active,
            false,
            reason: 'Pending HTTP must finish before audio acquisition',
          );
          expect(audio.playing, false);
          expect(requests, 1);
          heldExperiment.complete(
            http.Response(
              jsonEncode(ExperimentConfig.defaults().toJson()),
              200,
            ),
          );
        }
        for (
          var i = 0;
          i < 25 && find.textContaining('Aktiv tid').evaluate().isEmpty;
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        expect(service.active, true);
        expect(find.textContaining('Aktiv tid'), findsOneWidget);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
        expect(
          requests,
          obsolete ? 1 : 2,
          reason: 'No new HTTP may start during meditation',
        );
        expect(find.textContaining('Belöningen'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.runAsync(() async {
          await db.close();
          await dir.delete(recursive: true);
        });
      },
    );
  }
}
