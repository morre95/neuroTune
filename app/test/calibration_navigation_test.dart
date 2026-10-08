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
import 'package:neurotune/data/api_client.dart';
import 'package:neurotune/data/auth_store.dart';
import 'package:neurotune/data/database.dart';
import 'package:neurotune/main.dart';
import 'package:neurotune/platform/channels.dart';
import 'package:neurotune/ui/auth_page.dart';
import 'package:neurotune/ui/contact_page.dart';
import 'profile_library_test.dart' show wave, metadata, owner, version;
import 'meditation_session_test.dart' show PlaybackAudio, KeepAlive;

void main() {
  for (final logout in [true, false]) {
    testWidgets(
      logout
          ? 'a delayed calibration read cannot navigate after logout'
          : 'a delayed calibration read cannot replace a later contact screen',
      (tester) async {
        var requests = 0;
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
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        final hold = Completer<void>();
        final acquired = Completer<void>();
        late Future<void> block;
        await tester.runAsync(() async {
          block = db.transaction(() async {
            await db.customSelect('SELECT 1').get();
            acquired.complete();
            await hold.future;
          });
        });
        for (var n = 0; n < 25 && !acquired.isCompleted; n++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        expect(acquired.isCompleted, true);
        await tester.scrollUntilVisible(find.text('Kalibrering'), 200);
        await tester.pump();
        await tester.tap(find.text('Kalibrering'));
        await tester.pump();
        if (logout) {
          await tester.tap(find.text('Logga ut'));
        } else {
          await tester.scrollUntilVisible(find.text('Simulator'), -200);
          await tester.tap(find.text('Simulator'));
        }
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
        final destination = find.byType(logout ? AuthPage : ContactPage);
        expect(destination, findsOneWidget);
        hold.complete();
        await tester.pump();
        await tester.runAsync(() => block.timeout(const Duration(seconds: 3)));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
        expect(
          destination,
          findsOneWidget,
          reason:
              'A stale calibration read must preserve the later destination',
        );
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.runAsync(() => dir.delete(recursive: true));
      },
    );
  }
}
