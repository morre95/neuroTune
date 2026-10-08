import 'package:flutter/material.dart';
import '../data/meditation_sync_repository.dart';

/// Shows delivery state without exposing blinded calibration actions or errors
/// containing raw server metadata. Draft ratings stay local until complete.
class MeditationSyncStatusView extends StatelessWidget {
  const MeditationSyncStatusView({super.key, required this.status});
  final Stream<MeditationSyncStatus> status;
  @override
  Widget build(BuildContext context) => StreamBuilder<MeditationSyncStatus>(
    stream: status,
    builder: (context, snapshot) {
      final state = snapshot.data;
      if (state == null || state.pending + state.synced == 0) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          state.pending == 0
              ? 'Synkroniserat med ditt konto.'
              : state.errors > 0
              ? '${state.pending} poster väntar på synk. Senaste försök misslyckades; ett nytt försök görs när anslutningen återkommer.'
              : '${state.pending} poster väntar på synk med ditt konto.',
        ),
      );
    },
  );
}
