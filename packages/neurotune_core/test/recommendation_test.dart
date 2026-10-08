import 'package:neurotune_core/neurotune_core.dart';
import 'package:test/test.dart';

void main() {
  test('combined calibration score gives equal weight to both ratings', () {
    for (final (busy, relaxed, expected) in [
      (2, 6, 7.0),
      (4, 8, 7.0),
      (0, 10, 10.0),
      (10, 0, 0.0),
      (0, 0, 5.0),
      (10, 10, 5.0),
    ]) {
      expect(
        combinedMeditationScore(
          MeditationFeedback(
            ownerAccountId: 'owner',
            sessionId: 'session',
            mentalBusyness: busy,
            relaxation: relaxed,
            revision: 1,
          ),
        ),
        expected,
      );
    }
    expect(
      () => combinedMeditationScore(
        const MeditationFeedback(
          ownerAccountId: 'owner',
          sessionId: 'session',
          revision: 1,
        ),
      ),
      throwsArgumentError,
    );
  });
}
