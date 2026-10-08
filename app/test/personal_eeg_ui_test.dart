import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurotune/ui/personal_model_status.dart';
import 'package:neurotune_core/neurotune_core.dart';
import 'profile_library_test.dart' show metadata, wave;

void main() {
  testWidgets(
    'readiness exposes validation and fixed fallback without unfinished assignment labels',
    (tester) async {
      final json =
          (jsonDecode(
                    File(
                      '../contracts/fixtures/personal_eeg.json',
                    ).readAsStringSync(),
                  )
                  as Map)['model']
              as Map<String, dynamic>;
      final model = PersonalEegModel.fromJson(json);
      final profile = AudioProfileVersion.fromJson(metadata(wave()));
      var refresh = 0;
      Future<void> show(
        PersonalEegModel? m, {
        EyeState eyes = EyeState.closed,
      }) => tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PersonalModelStatus(
              model: m,
              profile: profile,
              eyeState: eyes,
              origin: DataOrigin.simulator,
              onRefresh: () => refresh++,
            ),
          ),
        ),
      );
      await show(model);
      expect(find.textContaining('Stödd'), findsOneWidget);
      expect(find.textContaining('20 sessioner'), findsOneWidget);
      expect(find.textContaining('0.50'), findsOneWidget);
      expect(find.textContaining('0 Hz'), findsNothing);
      await tester.tap(find.text('Uppdatera EEG-modell'));
      expect(refresh, 1);
      await show(model, eyes: EyeState.open);
      expect(find.textContaining('Fast uppspelning'), findsOneWidget);
      await show(
        PersonalEegModel.fromJson({
          ...json,
          'status': 'insufficient',
          'reasons': ['At least twenty usable fixed sessions are required'],
        }),
      );
      expect(find.textContaining('Fast uppspelning'), findsOneWidget);
      await show(null);
      expect(find.textContaining('Fler skattade'), findsOneWidget);
    },
  );
}
