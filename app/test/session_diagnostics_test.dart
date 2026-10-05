import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurotune/ui/session_diagnostics.dart';
import 'package:neurotune_core/neurotune_core.dart';

SessionManifest manifest({
  int version = 1,
  List<SessionDiagnostic> events = const [],
}) {
  final config = ExperimentConfig.defaults();
  return SessionEngine(
    config: config,
    snapshot: BanditSnapshot.empty(
      experimentVersion: config.version,
      origin: DataOrigin.muse,
    ),
    sessionId: 'diagnostics',
    origin: DataOrigin.muse,
    mode: SessionMode.personal,
    eyeState: EyeState.open,
    sampleRateHz: 256,
    channelNames: ['EEG1'],
    seed: 1,
    startedAt: DateTime.utc(2026),
  ).manifest(diagnosticsVersion: version, diagnostics: events);
}

FeatureFrame frame(bool valid) => FeatureFrame(
  timeSeconds: valid ? 4 : 5,
  sampleRateHz: 256,
  rejected: false,
  reasons: [],
  channels: [
    ChannelFeature(
      name: 'EEG1',
      valid: valid,
      contact: valid ? 1 : 4,
      absoluteTheta: 1,
      absoluteAlpha: 1,
      absoluteBeta: 1,
      relativeTheta: 0.3,
      relativeAlpha: 0.3,
      relativeBeta: 0.3,
      totalPower: 3,
      reasons: valid ? [] : ['contact'],
    ),
  ],
);

Widget page(SessionManifest saved) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: SessionDiagnostics(
        manifest: saved,
        frames: [frame(true), frame(false)],
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'diagnostics distinguish missing markers and show channel causes',
    (tester) async {
      await tester.pumpWidget(
        page(
          manifest(
            events: const [
              SessionDiagnostic(
                timeSeconds: 0,
                type: 'battery',
                values: {'percent': 70},
              ),
              SessionDiagnostic(
                timeSeconds: 4,
                type: 'connection',
                values: {'state': 'disconnected'},
              ),
              SessionDiagnostic(
                timeSeconds: 8,
                type: 'connection',
                values: {'state': 'connected'},
              ),
              SessionDiagnostic(
                timeSeconds: 10,
                type: 'battery',
                values: {'percent': 65},
              ),
            ],
          ),
        ),
      );
      expect(find.text('EEG1: 50 % godkända'), findsOneWidget);
      expect(find.textContaining('dålig kontakt: 1 fönster'), findsOneWidget);
      expect(find.text('Batteri: 70 % → 65 %'), findsOneWidget);
      expect(find.text('Tid frånkopplad: 4.0 s'), findsOneWidget);
      expect(
        find.text('Störningsmarkörer: inga paket mottagna från Muse'),
        findsOneWidget,
      );
      expect(find.textContaining('Blinkmarkeringar: 0'), findsNothing);
      await tester.ensureVisible(find.text('Diagnostik över tid'));
      await tester.tap(find.text('Diagnostik över tid'));
      await tester.pumpAndSettle();
      expect(find.text('4.0 s · Anslutning'), findsOneWidget);
    },
  );

  testWidgets('old recordings do not present absent diagnostics as zeros', (
    tester,
  ) async {
    await tester.pumpWidget(page(manifest(version: 0)));
    expect(find.textContaining('äldre inspelning'), findsOneWidget);
    expect(find.textContaining('Tid frånkopplad'), findsNothing);
  });
}
