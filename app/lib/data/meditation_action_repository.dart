import 'dart:convert';
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
