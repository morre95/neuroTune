import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide KeepAlive;
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:neurotune/data/api_client.dart';
import 'package:neurotune/data/auth_store.dart';
import 'package:neurotune/data/database.dart';
import 'package:neurotune/data/repository.dart';
import 'package:neurotune_core/neurotune_core.dart';
import 'package:neurotune/main.dart';
import 'package:neurotune/platform/channels.dart';
import 'profile_library_test.dart' show wave, metadata, owner, version;
import 'meditation_session_test.dart' show KeepAlive;
import 'meditation_interruptions_test.dart' show InterruptedAudio;

void main() {
  for (final heldRefresh in [false, true]) {
    testWidgets(
      heldRefresh
          ? 'idle model HTTP finishes before audio acquisition and no session retries'
          : 'cached primary meditation acquires and plays without session HTTP retries',
      (tester) async {
        var requests = 0;
        final modelResponse = Completer<http.Response>();
        String? modelBody;
        final (dir, db, api, audio, service) = (await tester.runAsync(() async {
          final dir = await Directory.systemTemp.createTemp(
            'meditation-offline',
          );
          final db = AppDatabase(NativeDatabase.memory());
          final fixture =
              jsonDecode(
                    await File(
                      '../contracts/fixtures/personal_eeg.json',
                    ).readAsString(),
                  )
                  as Map;
          final model = Map<String, dynamic>.from(fixture['model'] as Map)
            ..['owner_account_id'] = owner;
          modelBody = jsonEncode(model);
          await db.putKv(
            'meditation_model:v1:$owner:simulator:meditation-1',
            jsonEncode(model),
          );
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
              if (heldRefresh &&
                  request.url.path == '/v1/meditation/models/latest') {
                return modelResponse.future;
              }
              throw const SocketException('No network');
            }),
          );
          final audio = InterruptedAudio()..autoPlay = true;
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
        await tester.scrollUntilVisible(find.textContaining('Stödd'), 150);
        expect(find.textContaining('Stödd'), findsOneWidget);
        if (heldRefresh) {
          await tester.scrollUntilVisible(
            find.text('Uppdatera EEG-modell').first,
            150,
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('Uppdatera EEG-modell').first);
          await tester.pump();
          for (var i = 0; i < 25 && requests == 0; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump();
          }
          expect(requests, 1);
        }
        await tester.scrollUntilVisible(find.text('Simulator'), -150);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Simulator'));
        await tester.pump(const Duration(seconds: 1));
        await tester.ensureVisible(find.text('Starta meditation'));
        await tester.tap(find.text('Starta meditation'));
        await tester.pump();
        if (heldRefresh) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump();
          expect(
            service.active,
            false,
            reason: 'A pending model request must finish before audio',
          );
          modelResponse.complete(http.Response(modelBody!, 200));
        }
        for (var i = 0; i < 25 && !service.active; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
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
        expect(
          find.text('Adaptiv meditation · tio aktiva minuter.'),
          findsOneWidget,
        );
        audio.events.add(const PcmInterruption('focus_loss_transient'));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump();
        expect(audio.playing, false);
        expect(find.text('Fortsätt'), findsOneWidget);
        // A durable queue entry must not trigger HTTP on the periodic retry tick.
        await tester.runAsync(() async {
          final repo = SessionRepository(db);
          final profile = AudioProfileVersion.fromJson(metadata(wave()));
          final protocol = MeditationProtocol(
            context: SessionContext(
              sessionId: 'queued-previous',
              origin: DataOrigin.simulator,
              eyeState: EyeState.closed,
              sampleRateHz: 256,
              channelNames: simulatorChannels,
              seed: 1,
              startedAt: DateTime.utc(2026),
            ),
            profile: profile,
            action: StimulusAction.control,
          );
          final raw = utf8.encode('{}');
          final checksum = sha256Hex(raw);
          final path = await repo.saveSession(
            manifest: protocol.manifest(checksum: checksum),
            decisions: [],
            frames: [],
            raw: raw,
            checksum: checksum,
            status: 'stopped',
          );
          await repo.enqueueUpload(
            'queued-previous',
            checksum,
            path,
            'owner@test',
          );
        });
        await tester.pump(const Duration(minutes: 2));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        expect(requests, heldRefresh ? 1 : 0);
        expect(find.textContaining('Belöningen'), findsNothing);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.runAsync(() => dir.delete(recursive: true));
      },
    );
  }
}
