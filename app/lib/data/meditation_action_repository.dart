import 'dart:convert';
import 'package:neurotune_core/neurotune_core.dart';
import 'database.dart';
import 'repository.dart';

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
      return MeditationActionStatistics.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
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
  Future<bool> save(
    MeditationActionStatistics stats, {
    required bool Function() isCurrent,
  }) => db.transaction(() async {
    // Snapshot before awaits: later session updates cannot alter this write.
    final value = jsonEncode(stats.toJson());
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
