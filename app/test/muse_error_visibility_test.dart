import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart' hide isNotNull, isNull;
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
import 'package:neurotune/ui/history_page.dart';
import 'package:neurotune/ui/contact_page.dart';
import 'profile_library_test.dart' show wave, metadata, owner, version;
import 'meditation_session_test.dart' show PlaybackAudio, KeepAlive;
import 'recommendation_ui_test.dart' show settleIo;

class PendingMuse extends MuseChannel {
  final attempt = Completer<void>();
  bool connected = false;
  @override
  Future<void> start() async {
    await attempt.future;
    connected = true;
  }

  @override
  Future<void> stop() async {
    connected = false;
  }
}

Future<Directory> mountMeditation(WidgetTester tester, PendingMuse muse) async {
  tester.view.physicalSize = const Size(390, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final (dir, db) = (await tester.runAsync(() async {
    final dir = await Directory.systemTemp.createTemp('muse-start-error');
    final db = AppDatabase(NativeDatabase.memory());
    final bytes = wave();
    final folder = await Directory(
      '${dir.path}/audio_profiles/$owner',
    ).create(recursive: true);
    final file = await File('${folder.path}/$version.wav').writeAsBytes(bytes);
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
    return (dir, db);
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
      muse: muse,
      meditationEnabled: true,
    ),
  );
  await settleIo(tester);
  return dir;
}

void main() {
  testWidgets('Muse start failure is visible beside a scrolled start action', (
    tester,
  ) async {
    final muse = PendingMuse();
    final dir = await mountMeditation(tester, muse);
    await tester.scrollUntilVisible(find.text('Muse'), 150);
    await tester.tap(find.text('Muse'));
    await tester.pump();
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Ansluter…'),
          )
          .onPressed,
      null,
    );
    muse.attempt.completeError(
      PlatformException(
        code: 'BLUETOOTH_OFF',
        message: 'Bluetooth är avstängt.',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Bluetooth är avstängt.').hitTestable(), findsOneWidget);
    await settleIo(tester, 5);
    await tester.scrollUntilVisible(find.text('Muse'), 100);
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Muse'))
          .onPressed,
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox());
    await settleIo(tester, 5);
    await tester.runAsync(() => dir.delete(recursive: true));
  });
  for (final logout in [true, false]) {
    for (final succeeds in [true, false]) {
      testWidgets(
        '${logout ? 'logout' : 'history navigation'} ignores late Muse ${succeeds ? 'success' : 'failure'}',
        (tester) async {
          final muse = PendingMuse();
          final dir = await mountMeditation(tester, muse);
          await tester.scrollUntilVisible(find.text('Muse'), 150);
          await tester.tap(find.text('Muse'));
          await tester.pump();
          if (logout) {
            await tester.tap(find.text('Logga ut'));
          } else {
            await tester.scrollUntilVisible(find.text('Sessionshistorik'), 150);
            await tester.tap(find.text('Sessionshistorik'));
          }
          await settleIo(tester);
          if (succeeds) {
            muse.attempt.complete();
          } else {
            muse.attempt.completeError(
              PlatformException(
                code: 'BLUETOOTH_OFF',
                message: 'Bluetooth är avstängt.',
              ),
            );
          }
          await settleIo(tester);
          expect(find.byType(logout ? AuthPage : HistoryPage), findsOneWidget);
          expect(find.byType(ContactPage), findsNothing);
          expect(find.text('Bluetooth är avstängt.'), findsNothing);
          expect(muse.connected, false);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await settleIo(tester, 5);
          await tester.runAsync(() => dir.delete(recursive: true));
        },
      );
    }
  }
}
