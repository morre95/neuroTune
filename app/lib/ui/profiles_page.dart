import 'dart:async';
import 'package:flutter/material.dart';
import '../data/profile_library.dart';

class ProfilesPage extends StatelessWidget {
  const ProfilesPage({
    super.key,
    required this.library,
    required this.onBack,
    this.audioBusy = false,
  });
  final ProfileLibrary library;
  final Future<void> Function() onBack;
  final bool audioBusy;
  void _run(Future<void> future) {
    unawaited(future.catchError((Object _) {}));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: library,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const Text('Ljudprofiler'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _run(onBack()),
        ),
        actions: [
          IconButton(
            tooltip: 'Uppdatera',
            icon: const Icon(Icons.refresh),
            onPressed: () => _run(library.refresh()),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (library.offline) const Text('Offline. Sparade profiler visas.'),
          if (library.error != null) Text(library.error!),
          if (library.profiles.isEmpty)
            const Text(
              'Inga sparade ljudprofiler. Skapa en profil i ljudredigeraren.',
            ),
          for (final item in library.profiles)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${item.profile.name} · version ${item.profile.version}',
                    ),
                    Text(
                      item.downloaded
                          ? 'Nedladdad · redo offline'
                          : 'Redo på servern · inte nedladdad',
                    ),
                    if (library.progress[item.profile.id]
                        case final progress?) ...[
                      LinearProgressIndicator(value: progress.fraction),
                      Text('${(progress.fraction * 100).round()} %'),
                      TextButton(
                        onPressed: () =>
                            library.cancelDownload(item.profile.id),
                        child: const Text('Avbryt nedladdning'),
                      ),
                    ] else if (item.downloaded)
                      TextButton(
                        onPressed: library.previewId == item.profile.id
                            ? null
                            : () => _run(library.removeLocal(item.profile.id)),
                        child: const Text('Ta bort lokal kopia'),
                      )
                    else
                      FilledButton(
                        onPressed: library.offline
                            ? null
                            : () => _run(library.download(item.profile.id)),
                        child: const Text('Ladda ned'),
                      ),
                    if (library.previewId == item.profile.id)
                      TextButton(
                        onPressed: () => _run(library.stopPreview()),
                        child: const Text('Stoppa förhandslyssning'),
                      )
                    else
                      TextButton(
                        onPressed:
                            audioBusy ||
                                library.previewing ||
                                (library.offline && !item.downloaded)
                            ? null
                            : () => _run(library.preview(item.profile.id)),
                        child: const Text('Förhandslyssna · 30 s'),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
