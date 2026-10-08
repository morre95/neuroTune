import 'dart:convert';
import 'dart:io';
import 'package:neurotune_core/neurotune_core.dart';
import 'api_client.dart';
import 'meditation_sync_repository.dart';
import 'repository.dart';

class UploadSync {
  UploadSync({required this.repository, required this.api});
  final SessionRepository repository;
  final ApiClient api;
  late final meditation = MeditationSyncRepository(repository.db);
  Future<void>? _running;
  int _generation = 0;
  void cancel() => _generation++;
  Future<void> waitForIdle() async => await _running;
  Future<void> flush(String ownerEmail) =>
      _running ??= _flush(ownerEmail.toLowerCase()).whenComplete(() {
        _running = null;
      });

  Future<void> _flush(String email) async {
    final generation = _generation, authentication = api.authGeneration;
    final owner = api.accountId;
    bool valid() =>
        generation == _generation &&
        authentication == api.authGeneration &&
        owner == api.accountId;
    final deletions = await repository.pendingDeletions(email);
    for (var offset = 0; offset < deletions.length; offset += 100) {
      if (!valid()) return;
      final chunk = deletions.skip(offset).take(100).toList();
      try {
        await api.deleteSessions(chunk.map((job) => job.sessionId).toList());
        for (final job in chunk) {
          if (!valid()) return;
          await repository.completeDeletion(job);
        }
      } catch (error) {
        for (final job in chunk) {
          if (!valid()) return;
          await repository.markUpload(
            job.sessionId,
            'delete_pending',
            attempts: job.attempts + 1,
            error: '$error',
          );
        }
      }
    }
    if (owner != null) {
      for (final plan in await meditation.plans(owner)) {
        if (!valid()) return;
        try {
          await api.createCalibrationPlan(
            CalibrationPlan.fromJson(
              jsonDecode(plan.bodyJson) as Map<String, dynamic>,
            ),
          );
          if (!valid()) return;
          await meditation.markPlan(plan);
        } catch (error) {
          if (!valid()) return;
          await meditation.markPlan(plan, error: '$error');
        }
      }
    }
    final pending = await repository.pendingUploads();
    final sessions = {for (final s in await repository.listSessions()) s.id: s};
    for (final job in pending) {
      if (!valid()) return;
      if (job.ownerEmail != email) continue;
      final saved = sessions[job.sessionId];
      if (saved != null && isMeditation(saved.manifest)) {
        if (owner == null || meditationOwner(saved.manifest) != owner) continue;
        if (saved.manifest.meditation?['mode'] == 'calibration' &&
            !await meditation.planAccepted(
              owner,
              saved.manifest.meditation!['calibration_plan_id'] as String,
            )) {
          continue;
        }
      }
      try {
        if (saved == null) throw StateError('Session ${job.sessionId} saknas');
        final bytes = await File(job.payloadPath).readAsBytes();
        if (!valid()) return;
        final status = await api.uploadSession(
          manifest: saved.manifest,
          decisions: saved.decisions,
          frames: saved.frames,
          raw: bytes,
          checksum: job.checksum,
        );
        if (!valid()) return;
        if (status == 200 || status == 201) {
          if (!isMeditation(saved.manifest)) {
            await api.createTrainingJob(
              origin: saved.manifest.dataOrigin,
              experimentVersion: saved.manifest.experimentVersion,
            );
            if (!valid()) return;
          }
          await repository.markUpload(job.sessionId, 'done');
        } else if (status == 409) {
          await repository.markUpload(
            job.sessionId,
            'conflict',
            error: 'checksum',
          );
        }
      } catch (error) {
        if (!valid()) return;
        await repository.markUpload(
          job.sessionId,
          error is ApiException && error.status == 410 ? 'deleted' : 'pending',
          attempts: job.attempts + 1,
          error: '$error',
        );
        if (error is ApiException &&
            error.status == 410 &&
            owner != null &&
            saved != null &&
            meditationOwner(saved.manifest) == owner &&
            valid()) {
          await meditation.retireDeletedSession(owner, saved.id);
        }
      }
    }
    if (owner == null || !valid()) return;
    // Ratings may arrive days after raw upload. Never gate these stages on a
    // nonempty raw queue; each stage has its own durable delivery state.
    for (final row in await meditation.feedback(owner)) {
      final saved = sessions[row.sessionId];
      if (saved == null ||
          meditationOwner(saved.manifest) != owner ||
          !await meditation.rawAccepted(row.sessionId, email)) {
        continue;
      }
      if (!valid()) return;
      try {
        await api.saveMeditationFeedback(meditation.outcome(row));
        if (!valid()) return;
        await meditation.acknowledgeFeedback(row, saved);
      } catch (error) {
        if (!valid()) return;
        await meditation.failFeedback(
          row,
          error,
          gone: error is ApiException && error.status == 410,
        );
      }
    }
    for (final request in await meditation.training(owner)) {
      if (!valid()) return;
      final current = await meditation.trainingCurrent(request);
      final saved = (await repository.listSessions())
          .where((s) => s.id == request.sessionId)
          .firstOrNull;
      if (!valid()) return;
      if (!current || saved == null) {
        await meditation.markTraining(request, 'superseded');
        continue;
      }
      if (!await meditation.rawAccepted(request.sessionId, email)) continue;
      if (!valid()) return;
      try {
        await api.createMeditationTrainingJob(
          jsonDecode(request.bodyJson) as Map<String, dynamic>,
        );
        if (!valid()) return;
        // An edit while the request was held leaves the new revision pending.
        await meditation.markTraining(
          request,
          await meditation.trainingCurrent(request) ? 'done' : 'superseded',
        );
      } catch (error) {
        if (!valid()) return;
        await meditation.markTraining(
          request,
          error is ApiException && error.status == 410 ? 'deleted' : 'pending',
          error: error,
        );
      }
    }
  }
}
