import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurotune_core/neurotune_core.dart';

import 'package:neurotune/data/repository.dart';
import 'package:neurotune/ui/auth_page.dart';
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
          onHistory: () {},
          onLogout: () {},
        ),
      ),
    );
    expect(find.text('Simulator'), findsOneWidget);
    expect(find.textContaining('inte verifierat'), findsOneWidget);
    expect(find.textContaining('Offline'), findsOneWidget);
  });

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
