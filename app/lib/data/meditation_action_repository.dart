import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:neurotune_core/neurotune_core.dart';
import 'database.dart';
import 'repository.dart';
import 'meditation_sync_repository.dart';

/// Offline statistics, independent of the NIR bandit cache. The full model
/// evidence remains part of the provenance even for a setup with no fixed seeds.
class MeditationActionRepository {
  MeditationActionRepository(this.db, this.sessions);
  final AppDatabase db;
  final SessionRepository sessions;
  String key(MeditationActionStatistics stats) =>
      'meditation_action_stats:v1:${stats.owner}:${stats.setup.origin.name}:meditation-1:${stats.setup.key}:${stats.model.modelVersion}';
  Future<MeditationActionStatistics> load(
    String owner,
    MeditationSetupContext setup,
    PersonalEegModel model,
  ) => db.transaction(() async {
    if (!await _modelCurrent(owner, model)) {
      throw StateError('Learning model was revoked or superseded');
    }
    final seeds = MeditationActionStatistics.seeded(owner, setup, model);
    final raw = await db.getKv(key(seeds));
    if (raw == null) return seeds;
    try {
      final body = jsonDecode(raw) as Map<String, dynamic>;
      final parsed = MeditationActionStatistics.fromJson(
        body,
        owner,
        setup,
        model,
      );
      final reviewed = <Map<String, dynamic>>[];
      for (final contribution in parsed.contributions) {
        if (contribution['kind'] == 'fixed' ||
            await _reviewable(parsed, contribution)) {
          reviewed.add(contribution);
        }
      }
      return MeditationActionStatistics.fromJson(
        {...body, 'contributions': reviewed},
        owner,
        setup,
        model,
      );
    } on FormatException {
      return seeds;
    } on TypeError {
      return seeds;
    }
  });
  Future<bool> _modelCurrent(String owner, PersonalEegModel model) async {
    if (model.ownerAccountId != owner || model.status != 'ready') return false;
    final raw = await db.getKv(
      'meditation_model:v1:$owner:${model.origin}:meditation-1',
    );
    if (raw != null) {
      try {
        final body = jsonDecode(raw) as Map<String, dynamic>;
        if (body['missing'] == true || body['invalid'] == true) return false;
        final latest = PersonalEegModel.fromJson(body);
        if (latest.status != 'ready' ||
            latest.modelVersion != model.modelVersion ||
            latest.id != model.id ||
            latest.ownerAccountId != owner ||
            latest.origin != model.origin)
          return false;
      } on FormatException {
        return false;
      } on TypeError {
        return false;
      }
    }
    for (final evidence in model.evidence) {
      final sid = evidence['session_id'] as String;
      if (await sessions.isTombstoned(owner, sid)) return false;
      final row = await (db.select(
        db.storedSessions,
      )..where((r) => r.id.equals(sid))).getSingleOrNull();
      if (row != null) {
        final manifest = SessionManifest.fromJson(
          jsonDecode(row.manifestJson) as Map<String, dynamic>,
        );
        if (meditationOwner(manifest) == owner &&
            (row.origin != model.origin ||
                row.checksum != evidence['checksum_sha256']))
          return false;
      }
      final rating =
          await (db.select(db.meditationFeedbackRows)..where(
                (r) => r.ownerAccountId.equals(owner) & r.sessionId.equals(sid),
              ))
              .getSingleOrNull();
      if (rating != null && rating.revision != evidence['feedback_revision'])
        return false;
    }
    return true;
  }

  Future<bool> _reviewable(
    MeditationActionStatistics stats,
    Map<String, dynamic> contribution,
  ) async {
    final row =
        await (db.select(db.storedSessions)
              ..where((r) => r.id.equals(contribution['session_id'] as String)))
            .getSingleOrNull();
    if (row == null ||
        row.checksum != contribution['checksum_sha256'] ||
        !['completed', 'stopped'].contains(row.status)) {
      return false;
    }
    final manifest = SessionManifest.fromJson(
      jsonDecode(row.manifestJson) as Map<String, dynamic>,
    );
    final meta = manifest.meditation;
    if (meditationOwner(manifest) != stats.owner ||
        manifest.dataOrigin != stats.setup.origin.name ||
        meta?['mode'] != 'adaptive' ||
        meta?['model_version'] != stats.model.modelVersion ||
        meta?['model_id'] != stats.model.id ||
        meta?['statistics_setup_key'] != stats.setup.key ||
        meta?['adaptive_decisions'] is! List) {
      return false;
    }
    return (meta!['adaptive_decisions'] as List).any(
      (d) =>
          d is Map &&
          d['minute'] == contribution['minute'] &&
          d['action'] == contribution['action'] &&
          d['score'] == contribution['score'] &&
          d['updated_statistics'] == true &&
          d['model_version'] == stats.model.modelVersion,
    );
  }

  Future<bool> save(
    MeditationActionStatistics stats, {
    required bool Function() isCurrent,
  }) => db.transaction(() async {
    // Snapshot before awaits: later session updates cannot alter this write.
    final snapshot = stats.toJson();
    if (!isCurrent() || !await _modelCurrent(stats.owner, stats.model))
      return false;
    for (final contribution in stats.contributions) {
      if (contribution['kind'] == 'adaptive' &&
          !await _reviewable(stats, contribution)) {
        return false;
      }
    }
    final value = jsonEncode(snapshot);
    final ids = List<String>.of(stats.includedSessionIds);
    final epoch = await sessions.readEvidenceEpoch(stats.owner);
    return sessions.publishEvidenceCache(
      stats.owner,
      expectedLocalEpoch: epoch,
      includedSessionIds: ids,
      key: key(stats),
      value: value,
      isCurrent: isCurrent,
    );
  });
}
