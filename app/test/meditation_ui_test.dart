import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurotune/ui/meditation_home_page.dart';
import 'package:neurotune/ui/history_page.dart';
import 'package:neurotune/ui/playback_page.dart';
import 'package:neurotune/data/repository.dart';
import 'package:neurotune/data/profile_library.dart';
import 'package:neurotune_core/neurotune_core.dart';
import 'profile_library_test.dart' show wave, metadata;

void main() {
  testWidgets(
    'meditation shows the five fixed actions and gates undownloaded profiles',
    (tester) async {
      final profile = AudioProfileVersion.fromJson(metadata(wave()));
      var start = false;
      var experiments = false;
      Widget home(bool ready) => MaterialApp(
        home: MeditationHomePage(
          profiles: [LocalAudioProfile(profile, ready)],
          selectedProfileId: profile.id,
          action: StimulusAction.control,
          eyeState: EyeState.closed,
          onProfile: (_) {},
          onAction: (_) {},
          onEyeState: (_) {},
          onSimulator: () => start = true,
          onMuse: () {},
          onProfiles: () {},
          onExperiments: () => experiments = true,
          onHistory: () {},
          onLogout: () {},
        ),
      );
      await tester.pumpWidget(home(false));
      expect(find.text('Meditation'), findsOneWidget);
      for (final hz in [0, 6, 8, 10, 12]) {
        expect(find.text('$hz Hz'), findsOneWidget);
      }
      await tester.tap(find.text('Simulator'));
      expect(start, false);
      await tester.pumpWidget(home(true));
      await tester.tap(find.text('Simulator'));
      expect(start, true);
      await tester.ensureVisible(find.text('Experiments'));
      await tester.tap(find.text('Experiments'));
      expect(experiments, true);
    },
  );
  testWidgets(
    'meditation history retains its fixed action and completed outcome without a NIR baseline',
    (tester) async {
      final profile = AudioProfileVersion.fromJson(metadata(wave()));
      final protocol = MeditationProtocol(
        context: SessionContext(
          sessionId: 'meditation',
          origin: DataOrigin.simulator,
          eyeState: EyeState.closed,
          sampleRateHz: 256,
          channelNames: simulatorChannels,
          seed: 1,
          startedAt: DateTime.utc(2026),
        ),
        profile: profile,
        action: StimulusAction.binaural6,
      );
      protocol.playback(600 * 48000, 600);
      final manifest = SessionManifest.fromJson(protocol.manifest().toJson());
      final saved = SavedSession(
        id: manifest.sessionId,
        origin: manifest.dataOrigin,
        mode: manifest.mode,
        manifest: manifest,
        decisions: [],
        frames: [],
        status: 'completed',
        checksum: '',
        createdAt: DateTime.utc(2026),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: HistoryPage(sessions: [saved], onOpen: (_) {}, onBack: () {}),
        ),
      );
      expect(
        find.textContaining('Meditation · Binauralt 6 Hz'),
        findsOneWidget,
      );
      expect(find.textContaining('Slutförd'), findsOneWidget);
      expect(find.textContaining('baslinjen'), findsNothing);
      await tester.pumpWidget(
        MaterialApp(
          home: PlaybackPage(session: saved, onBack: () {}),
        ),
      );
      expect(find.text('Åtgärd: Binauralt 6 Hz'), findsOneWidget);
      expect(find.textContaining('Yttre NIR'), findsNothing);
    },
  );
}
