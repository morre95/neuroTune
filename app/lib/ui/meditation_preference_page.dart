import 'package:flutter/material.dart';
import 'package:neurotune_core/neurotune_core.dart';
import '../data/meditation_preference_repository.dart';
import 'session_page.dart';

class MeditationPreferencePage extends StatefulWidget {
  const MeditationPreferencePage({
    super.key,
    required this.choice,
    required this.results,
    required this.onChoose,
    required this.onAdditionalSeries,
    required this.onBack,
  });
  final FixedMeditationChoice choice;
  final List<CalibrationSlotResult> results;
  final Future<void> Function(StimulusAction) onChoose;
  final Future<void> Function() onAdditionalSeries;
  final VoidCallback onBack;
  @override
  State<MeditationPreferencePage> createState() =>
      _MeditationPreferencePageState();
}

class _MeditationPreferencePageState extends State<MeditationPreferencePage> {
  bool _busy = false;
  String? _error;
  Future<void> _perform(Future<void> Function() work) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await work();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final choice = widget.choice;
    final setup = choice.setup;
    final recommendation = choice.recommendation;
    return Scaffold(
      appBar: AppBar(title: const Text('Resultat och fast ton')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            '${setup.profile.name} · v${setup.profile.version} · ${setup.origin.name} · ${setup.eyeState == EyeState.closed ? 'stängda' : 'öppna'} ögon',
          ),
          Text(
            'Bärare ${setup.profile.carrierHz.toStringAsFixed(0)} Hz · tongain ${setup.profile.toneGain} · bakgrundsgain ${setup.profile.backgroundGain}',
          ),
          const SizedBox(height: 16),
          if (recommendation == null)
            const Text(
              'Ingen skattad kalibreringssession kvar för denna datakälla.',
            )
          else ...[
            Text('Rekommenderad: ${actionLabel(recommendation.action.id)}'),
            Text(
              recommendation.pooled
                  ? 'Jämförelse från andra uppsättningar med samma datakälla.'
                  : 'Jämförelse för denna uppsättning.',
            ),
            Text(
              '${recommendation.sessionCount} fullständigt skattade kalibreringssessioner. Poäng: (avslappning + 10 − mental upptagenhet) / 2.',
            ),
            for (final action in fixedActionOrder)
              if (recommendation.means[action] case final mean?)
                Text(
                  '${actionLabel(action.id)} · medel ${mean.toStringAsFixed(1)} · ${recommendation.counts[action]} sessioner',
                ),
          ],
          const SizedBox(height: 16),
          Text('Vald fast ton: ${actionLabel(choice.action.id)}'),
          Text(
            choice.preference == null
                ? 'Rekommendationen används tills du väljer en egen ton.'
                : 'Ditt sparade val används för denna uppsättning och datakälla.',
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final action in fixedActionOrder)
                ChoiceChip(
                  label: Text(actionLabel(action.id)),
                  selected: choice.action == action,
                  onSelected: _busy
                      ? null
                      : (_) => _perform(() => widget.onChoose(action)),
                ),
            ],
          ),
          if (_error != null) Text(_error!),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : () => _perform(widget.onAdditionalSeries),
            child: const Text('Samla en serie till'),
          ),
          const Text(
            'En ny balanserad serie låser samma profil, ögonläge och datakälla. Välj en annan uppsättning på meditationssidan för en annan serie.',
          ),
          if (widget.results.isNotEmpty) ...[
            const Divider(),
            const Text('Slutförd serie · skattningar och toninställningar'),
            for (final result in widget.results) ...[
              Text(
                'Session ${result.slot + 1}: ${actionLabel(result.action.id)}',
              ),
              Text(
                'Mental upptagenhet ${result.feedback.mentalBusyness} · Avslappning ${result.feedback.relaxation} · Poäng ${result.score.toStringAsFixed(1)}',
              ),
            ],
          ],
          TextButton(
            onPressed: _busy ? null : widget.onBack,
            child: const Text('Tillbaka'),
          ),
        ],
      ),
    );
  }
}
