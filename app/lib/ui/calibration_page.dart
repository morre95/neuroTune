import 'package:flutter/material.dart';
import 'package:neurotune_core/neurotune_core.dart';
import '../data/calibration_repository.dart';
import '../data/repository.dart';
import 'session_page.dart';

class CalibrationPage extends StatelessWidget {
  const CalibrationPage({
    super.key,
    required this.progress,
    required this.profile,
    required this.eyeState,
    required this.onNewSeries,
    required this.onResume,
    required this.onFeedback,
    required this.onBack,
    this.busy = false,
    this.pendingFeedback = const [],
    this.message,
    this.syncStatus,
  });
  final List<CalibrationProgress> progress;
  final List<SavedSession> pendingFeedback;
  final AudioProfileVersion? profile;
  final EyeState eyeState;
  final ValueChanged<DataOrigin> onNewSeries;
  final ValueChanged<CalibrationPlan> onResume;
  final ValueChanged<SavedSession> onFeedback;
  final VoidCallback onBack;
  final bool busy;
  final Widget? syncStatus;
  final String? message;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Kalibrering')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Tio sessioner med dolda toninställningar. Varje session varar tio aktiva minuter. '
          'Ljudprofil och ögonläge låses för hela serien. Båda skattningarna krävs efter varje session.',
        ),
        if (message != null) Text(message!),
        ?syncStatus,
        const SizedBox(height: 16),
        if (profile case final p?) ...[
          Text(
            'Ny serie: ${p.name} · v${p.version} · ${eyeState == EyeState.closed ? 'stängda' : 'öppna'} ögon',
          ),
          FilledButton(
            onPressed: busy ? null : () => onNewSeries(DataOrigin.simulator),
            child: const Text('Ny serie · Simulator'),
          ),
          OutlinedButton(
            onPressed: busy ? null : () => onNewSeries(DataOrigin.muse),
            child: const Text('Ny serie · Muse'),
          ),
        ] else
          const Text(
            'Välj en nedladdad ljudprofil på meditationssidan för att börja en ny serie.',
          ),
        for (final session in pendingFeedback.where(
          (s) => s.manifest.meditation?['mode'] != 'calibration',
        )) ...[
          const Divider(),
          Text(
            'Meditation ${session.manifest.startedAtIso} · återkoppling väntar',
          ),
          FilledButton(
            onPressed: busy ? null : () => onFeedback(session),
            child: const Text('Slutför återkoppling'),
          ),
        ],
        for (var index = 0; index < progress.length; index++) ...[
          const Divider(),
          Text(
            'Serie ${progress.length - index} · ${progress[index].completedSlots}/10 slutförda',
          ),
          Text(
            '${progress[index].plan.profile.name} · v${progress[index].plan.profile.version} · '
            '${progress[index].plan.origin.name} · ${progress[index].plan.eyeState == EyeState.closed ? 'stängda' : 'öppna'} ögon',
          ),
          if (!progress[index].complete)
            const Text('Toninställningarna visas när hela serien är slutförd.'),
          for (final session in progress[index].awaitingFeedback)
            FilledButton(
              onPressed: busy ? null : () => onFeedback(session),
              child: const Text('Slutför återkoppling'),
            ),
          if (!progress[index].complete &&
              progress[index].awaitingFeedback.isEmpty)
            FilledButton(
              onPressed: busy ? null : () => onResume(progress[index].plan),
              child: Text(
                'Fortsätt serie · session ${(progress[index].nextSlot ?? 0) + 1}',
              ),
            ),
          if (progress[index].complete)
            for (var slot = 0; slot < 10; slot++)
              Text(
                'Session ${slot + 1}: ${actionLabel(progress[index].plan.schedule[slot].id)}',
              ),
        ],
        TextButton(
          onPressed: busy ? null : onBack,
          child: const Text('Tillbaka'),
        ),
      ],
    ),
  );
}
