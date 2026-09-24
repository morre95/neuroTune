import 'dart:io';

import 'api_client.dart';
import 'repository.dart';

class UploadSync {
  UploadSync({required this.repository, required this.api});

  final SessionRepository repository;
  final ApiClient api;
  Future<void>? _running;
  int _generation = 0;

  void cancel() => _generation++;

  Future<void> waitForIdle() async => await _running;

  Future<void> flush(String ownerEmail) =>
      _running ??= _flush(ownerEmail.toLowerCase()).whenComplete(() {
        _running = null;
      });

  Future<void> _flush(String ownerEmail) async {
    final generation = _generation;
    final pending = await repository.pendingUploads();
    if (generation != _generation) return;
    if (pending.isEmpty) return;
    final sessions = {
      for (final session in await repository.listSessions())
        session.id: session,
    };
    for (final job in pending) {
      if (generation != _generation) return;
      if (job.ownerEmail != ownerEmail) continue;
      try {
        final saved = sessions[job.sessionId];
        if (saved == null) throw StateError('Session ${job.sessionId} saknas');
        final bytes = await File(job.payloadPath).readAsBytes();
        final status = await api.uploadSession(
          manifest: saved.manifest,
          decisions: saved.decisions,
          frames: saved.frames,
          raw: bytes,
          checksum: job.checksum,
        );
        if (generation != _generation) return;
        if (status == 200 || status == 201) {
          await api.createTrainingJob(
            origin: saved.manifest.dataOrigin,
            experimentVersion: saved.manifest.experimentVersion,
          );
          await repository.markUpload(job.sessionId, 'done');
        } else if (status == 409) {
          await repository.markUpload(
            job.sessionId,
            'conflict',
            error: 'checksum',
          );
        }
      } catch (error) {
        await repository.markUpload(
          job.sessionId,
          'pending',
          attempts: job.attempts + 1,
          error: '$error',
        );
      }
    }
  }
}
