import 'package:flutter/material.dart';
import 'package:neurotune_core/neurotune_core.dart';

/// Aggregate validation only; never exposes unfinished calibration assignments.
class PersonalModelStatus extends StatelessWidget {
  const PersonalModelStatus({
    super.key,
    required this.model,
    required this.profile,
    required this.eyeState,
    required this.origin,
    required this.onRefresh,
    this.busy = false,
    this.message,
    this.eegConfig,
  });
  final PersonalEegModel? model;
  final AudioProfileVersion? profile;
  final EyeState eyeState;
  final DataOrigin origin;
  final VoidCallback? onRefresh;
  final bool busy;
  final String? message;
  final ExperimentConfig? eegConfig;
  @override
  Widget build(BuildContext context) {
    final p = profile;
    final reason = model == null
        ? 'Fler skattade fasta sessioner behövs (minst 20 med användbar EEG).'
        : p == null
        ? 'Välj en ljudprofil.'
        : model!.unsupportedReason(
            backgroundAssetId: p.backgroundAssetId,
            eyeState: eyeState.name,
            carrierHz: p.carrierHz,
            toneGain: p.toneGain,
            backgroundGain: p.backgroundGain,
            eegConfig: eegConfig,
          );
    final validation = model?.validation;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'EEG-modell · ${origin.name}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              reason == null
                  ? 'Stödd för vald profil och ögonläge'
                  : 'Fast uppspelning · $reason',
            ),
            if (validation != null)
              Text(
                '${validation['session_count']} sessioner · MAE ${_metric(validation['mae'])} · korrelation ${_metric(validation['correlation'])} · kontext-MAE ${_metric(validation['context_mae'])}',
              ),
            if (origin != DataOrigin.muse)
              const Text(
                'Simulator/playback är separat från Muse. Syntetiska data visar inte fysisk EEG-effekt.',
              ),
            if (reason != null)
              const Text(
                'Samla fler fasta sessioner med båda efter-skattningarna; kalibrering finns nedan.',
              ),
            if (message != null) Text(message!),
            TextButton(
              onPressed: busy ? null : onRefresh,
              child: Text(busy ? 'Uppdaterar…' : 'Uppdatera EEG-modell'),
            ),
          ],
        ),
      ),
    );
  }

  String _metric(dynamic n) => n is num ? n.toStringAsFixed(2) : '—';
}
