import 'package:flutter/material.dart';
import 'package:neurotune_core/neurotune_core.dart';
import '../data/profile_library.dart';

class MeditationHomePage extends StatelessWidget {
  const MeditationHomePage({
    super.key,
    required this.profiles,
    required this.selectedProfileId,
    required this.action,
    required this.eyeState,
    required this.onProfile,
    required this.onAction,
    required this.onEyeState,
    required this.onSimulator,
    required this.onMuse,
    required this.onProfiles,
    required this.onExperiments,
    required this.onHistory,
    required this.onLogout,
    this.connectingMuse = false,
    this.message,
  });
  final List<LocalAudioProfile> profiles;
  final String? selectedProfileId;
  final StimulusAction action;
  final EyeState eyeState;
  final ValueChanged<String?> onProfile;
  final ValueChanged<StimulusAction> onAction;
  final ValueChanged<EyeState> onEyeState;
  final VoidCallback onSimulator,
      onMuse,
      onProfiles,
      onExperiments,
      onHistory,
      onLogout;
  final bool connectingMuse;
  final String? message;
  @override
  Widget build(BuildContext context) {
    final selected = profiles.where((p) => p.profile.id == selectedProfileId);
    final ready = selected.isNotEmpty && selected.first.downloaded;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meditation'),
        actions: [
          TextButton(onPressed: onLogout, child: const Text('Logga ut')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Tio minuter med ditt nedladdade ljud och en fast toninställning.',
          ),
          if (message != null) Text(message!),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            key: ValueKey(selectedProfileId),
            initialValue: selected.isEmpty ? null : selectedProfileId,
            decoration: const InputDecoration(labelText: 'Ljudprofil'),
            isExpanded: true,
            items: [
              for (final p in profiles)
                DropdownMenuItem(
                  value: p.profile.id,
                  child: Text(
                    '${p.profile.name} · v${p.profile.version}${p.downloaded ? '' : ' · inte nedladdad'}',
                  ),
                ),
            ],
            onChanged: onProfile,
          ),
          TextButton(onPressed: onProfiles, child: const Text('Ljudprofiler')),
          if (!ready)
            const Text(
              'Ladda ned och verifiera en ljudprofil innan du börjar.',
            ),
          const SizedBox(height: 12),
          const Text('Fast frekvensskillnad'),
          Wrap(
            spacing: 8,
            children: [
              for (final a in [
                StimulusAction.control,
                StimulusAction.binaural6,
                StimulusAction.binaural8,
                StimulusAction.binaural10,
                StimulusAction.binaural12,
              ])
                ChoiceChip(
                  label: Text('${a.beatHz.toInt()} Hz'),
                  selected: action == a,
                  onSelected: (_) => onAction(a),
                ),
            ],
          ),
          const SizedBox(height: 16),
          SegmentedButton<EyeState>(
            segments: const [
              ButtonSegment(
                value: EyeState.closed,
                label: Text('Stängda ögon'),
              ),
              ButtonSegment(value: EyeState.open, label: Text('Öppna ögon')),
            ],
            selected: {eyeState},
            onSelectionChanged: (v) => onEyeState(v.single),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: ready ? onSimulator : null,
            child: const Text('Simulator'),
          ),
          OutlinedButton(
            onPressed: ready && !connectingMuse ? onMuse : null,
            child: Text(connectingMuse ? 'Ansluter…' : 'Muse'),
          ),
          TextButton(
            onPressed: onHistory,
            child: const Text('Sessionshistorik'),
          ),
          TextButton(
            onPressed: onExperiments,
            child: const Text('Experiments'),
          ),
        ],
      ),
    );
  }
}
