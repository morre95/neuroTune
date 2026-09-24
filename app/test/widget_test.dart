import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurotune_core/neurotune_core.dart';

import 'package:neurotune/data/repository.dart';
import 'package:neurotune/ui/auth_page.dart';
import 'package:neurotune/ui/contact_page.dart';
import 'package:neurotune/ui/history_page.dart';
import 'package:neurotune/ui/home_page.dart';
import 'package:neurotune/ui/playback_page.dart';
import 'package:neurotune/ui/session_page.dart';

void main() {
  testWidgets('registration form submits email and password', (tester) async {
    String? email;
    var register = false;
    await tester.pumpWidget(
      MaterialApp(
        home: AuthPage(
          onSubmit: (value, password, creating) async {
            email = value;
            register = creating;
          },
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).at(0), 'person@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'correct-horse');
    await tester.tap(find.text('Registrera'));
    await tester.pump();
    expect(email, 'person@example.com');
    expect(register, isTrue);
  });

  testWidgets('home explains that Muse hardware is not verified', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          experimentVersion: '2026.1',
          policyVersion: '0',
          hardwareApproved: false,
          offline: true,
          eyeState: EyeState.open,
          mode: SessionMode.personal,
          onEyeState: (_) {},
          onMode: (_) {},
          onStartSimulator: () {},
          onMuse: () {},
          connectingMuse: false,
          onHistory: () {},
          onLogout: () {},
        ),
      ),
    );
    expect(find.text('Simulator'), findsOneWidget);
    expect(find.textContaining('inte verifierat'), findsOneWidget);
    expect(find.textContaining('Offline'), findsOneWidget);
  });

  testWidgets('home describes the selected session mode', (tester) async {
    Widget home(SessionMode mode) => MaterialApp(
      home: HomePage(
        experimentVersion: '2026.1',
        policyVersion: '0',
        hardwareApproved: true,
        offline: false,
        eyeState: EyeState.open,
        mode: mode,
        onEyeState: (_) {},
        onMode: (_) {},
        onStartSimulator: () {},
        onMuse: () {},
        connectingMuse: false,
        onHistory: () {},
        onLogout: () {},
      ),
    );

    await tester.pumpWidget(home(SessionMode.personal));
    expect(find.text(modeDescription(SessionMode.personal)), findsOneWidget);
    expect(find.text(modeDescription(SessionMode.comparison)), findsNothing);

    await tester.pumpWidget(home(SessionMode.comparison));
    expect(find.text(modeDescription(SessionMode.comparison)), findsOneWidget);
    expect(find.text(modeDescription(SessionMode.personal)), findsNothing);
  });

  testWidgets(
    'headphone test is available before baseline and can be stopped',
    (tester) async {
      var taps = 0;

      Widget page({required bool playing}) => MaterialApp(
        home: ContactPage(
          batch: null,
          onStart: () {},
          onBack: () {},
          onStereoTest: () => taps++,
          stereoTestPlaying: playing,
          stereoTestBusy: false,
        ),
      );

      await tester.pumpWidget(page(playing: false));
      expect(find.text('Testa hörlurar'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Starta baslinje'),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('Testa hörlurar'));
      expect(taps, 1);

      await tester.pumpWidget(page(playing: true));
      expect(find.text('Stoppa hörlurstest'), findsOneWidget);
      await tester.tap(find.text('Stoppa hörlurstest'));
      expect(taps, 2);
    },
  );

  testWidgets('session shows theta, alpha, beta, quality and the action', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SessionPage(
          view: const SessionView(
            message: 'Ljudblock 1.',
            phase: 'sound',
            blockLabel: '0/15',
            actionLabel: 'Binauralt 10 Hz',
            theta: '0.420',
            alpha: '0.210',
            beta: '0.080',
            outerNir: '20.000',
            nirZ: '0.500',
            quality: '4/4 kanaler',
            canContinue: false,
            canStop: true,
          ),
          onStop: () {},
          onContinue: () {},
          onFinish: () {},
        ),
      ),
    );
    expect(find.text('Theta 0.420'), findsOneWidget);
    expect(find.text('Alpha 0.210'), findsOneWidget);
    expect(find.text('Beta 0.080'), findsOneWidget);
    expect(find.text('Yttre NIR 20.000 µA'), findsOneWidget);
    expect(find.text('NIR-z 0.500'), findsOneWidget);
    expect(find.text('Signalkvalitet 4/4 kanaler'), findsOneWidget);
    expect(find.text('Åtgärd: Binauralt 10 Hz'), findsOneWidget);
    expect(find.textContaining('Inte syresättning'), findsOneWidget);
  });

  testWidgets('session swaps stop for resume while paused', (tester) async {
    Widget page({required bool canContinue, required bool canStop}) => MaterialApp(
      home: SessionPage(
        view: SessionView(
          message: 'Signalen avbröts.',
          phase: 'waitingStable',
          blockLabel: '2/15',
          actionLabel: 'Tystnad',
          theta: '-',
          alpha: '-',
          beta: '-',
          outerNir: '-',
          nirZ: '-',
          quality: '-',
          canContinue: canContinue,
          canStop: canStop,
        ),
        onStop: () {},
        onContinue: () {},
        onFinish: () {},
      ),
    );

    await tester.pumpWidget(page(canContinue: false, canStop: true));
    expect(find.text('Stoppa'), findsOneWidget);
    expect(find.text('Fortsätt'), findsNothing);

    await tester.pumpWidget(page(canContinue: true, canStop: false));
    expect(find.text('Fortsätt'), findsOneWidget);
    expect(find.text('Stoppa'), findsNothing);

    await tester.pumpWidget(page(canContinue: false, canStop: false));
    expect(find.text('Stoppa'), findsNothing);
    expect(find.text('Fortsätt'), findsNothing);
    expect(find.text('Avsluta session'), findsOneWidget);
  });

  testWidgets('history explains a session that recorded no blocks', (
    tester,
  ) async {
    SavedSession empty({String? stopReason, List<String> selected = const []}) =>
        SavedSession(
          id: 'e',
          origin: 'muse',
          mode: 'personal',
          manifest: SessionManifest(
            sessionId: 'e',
            userId: null,
            experimentVersion: '2026.2',
            policyVersion: '0',
            dataOrigin: 'muse',
            mode: 'personal',
            eyeState: 'closed',
            sampleRateHz: 256,
            channelNames: const ['EEG1', 'EEG2', 'EEG3', 'EEG4'],
            selectedChannels: selected,
            startedAtIso: '2026-09-24T09:00:00Z',
            durationSeconds: 125,
            audioLatencyMs: 40,
            audioLatencySource: 'audiotrack_buffer_frames',
            timeline: 'monotonic_session_seconds',
            seed: 1,
            checksumSha256: 'abc',
            stopReason: stopReason,
          ),
          decisions: const [],
          frames: const [],
          status: 'stopped',
          checksum: 'abc',
          createdAt: DateTime.utc(2026, 9, 24),
        );

    Widget history(SavedSession session) => MaterialApp(
      home: HistoryPage(
        sessions: [session],
        onOpen: (_) {},
        onBack: () {},
      ),
    );

    await tester.pumpWidget(history(empty(stopReason: 'baselineFailed')));
    expect(find.textContaining('0 block'), findsOneWidget);
    expect(find.textContaining('2m 5s'), findsOneWidget);
    expect(find.textContaining('baslinjen underkändes'), findsOneWidget);

    await tester.pumpWidget(history(empty()));
    expect(
      find.textContaining('Stoppad innan baslinjen godkändes'),
      findsOneWidget,
    );
  });

  testWidgets('playback steps to the next second', (tester) async {
    final session = SavedSession(
      id: 's',
      origin: 'simulator',
      mode: 'personal',
      manifest: SessionManifest(
        sessionId: 's',
        userId: null,
        experimentVersion: '2026.1',
        policyVersion: '0',
        dataOrigin: 'simulator',
        mode: 'personal',
        eyeState: 'open',
        sampleRateHz: 256,
        channelNames: simulatorChannels,
        selectedChannels: simulatorChannels,
        startedAtIso: '2026-09-23T12:00:00Z',
        durationSeconds: 2,
        audioLatencyMs: 40,
        audioLatencySource: 'audiotrack_buffer_frames',
        timeline: 'monotonic_session_seconds',
        seed: 1,
        checksumSha256: 'abc',
      ),
      decisions: [
        DecisionEvent(
          sessionId: 's',
          blockIndex: 0,
          attemptIndex: 0,
          action: 'control',
          selectionProbability: 0.2,
          reward: 0.1,
          meanAbsoluteTheta: 3,
          validFraction: 1,
          updatedBandit: true,
          experimentVersion: '2026.1',
          policyVersion: '0',
          qualityVersion: '2026.1-sim',
          startedAtSeconds: 0,
          endedAtSeconds: 1,
          aborted: false,
        ),
      ],
      frames: [_frame(0, 0.1), _frame(1, 0.4)],
      status: 'completed',
      checksum: 'abc',
      createdAt: DateTime.utc(2026, 9, 23),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PlaybackPage(session: session, onBack: () {}),
      ),
    );
    expect(find.text('Theta 0.100'), findsOneWidget);
    await tester.tap(find.text('Nästa sekund'));
    await tester.pump();
    expect(find.text('Theta 0.400'), findsOneWidget);
    expect(find.text('Åtgärd: Kontroll'), findsOneWidget);
  });
}

FeatureFrame _frame(double time, double theta) {
  return FeatureFrame(
    timeSeconds: time,
    sampleRateHz: 256,
    rejected: false,
    reasons: const [],
    channels: [
      for (final name in simulatorChannels)
        ChannelFeature(
          name: name,
          valid: true,
          contact: 1,
          absoluteTheta: 1,
          absoluteAlpha: 1,
          absoluteBeta: 1,
          relativeTheta: theta,
          relativeAlpha: 0.2,
          relativeBeta: 0.1,
          totalPower: 1,
          reasons: const [],
        ),
    ],
  );
}
