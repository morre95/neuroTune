import 'dart:convert';
import 'package:neurotune_core/neurotune_core.dart';
import 'database.dart';
import 'repository.dart';
import 'calibration_repository.dart';
import 'api_client.dart';
import 'meditation_sync_repository.dart';
import 'meditation_learning_cleanup.dart';

/// Versioned account/source cache. An evidence epoch guards a new publication;
/// it is never a blanket revocation clock for an unaffected offline artifact.
class PersonalEegRepository {
  PersonalEegRepository(this.db, this.sessions, this.calibration, this.api);
  final AppDatabase db;
  final SessionRepository sessions;
  final CalibrationRepository calibration;
  final ApiClient api;
  String _key(String owner, DataOrigin origin) {
    if (!isAccountUuid(owner)) throw ArgumentError('Account UUID required');
    return 'meditation_model:v1:$owner:${origin.name}:meditation-1';
  }

  Future<bool> _evidenceCurrent(String owner, PersonalEegModel model) async {
    final local = {
      for (final s in await sessions.listSessions())
        if (meditationOwner(s.manifest) == owner) s.id: s,
    };
    for (final e in model.evidence) {
      final sid = e['session_id'] as String;
      if (await sessions.isTombstoned(owner, sid)) return false;
      final record = local[sid];
      // An authenticated artifact may include evidence from another device.
      if (record == null) continue;
      if (record.origin != model.origin ||
          record.checksum != e['checksum_sha256']) {
        return false;
      }
      final rating = await calibration.feedback(owner, sid);
      if (rating != null && rating.revision != e['feedback_revision']) {
        return false;
      }
    }
    return true;
  }

  Future<PersonalEegModel?> load(String owner, DataOrigin origin) =>
      db.transaction(() async {
        final raw = await db.getKv(_key(owner, origin));
        if (raw == null) return null;
        try {
          final json = jsonDecode(raw) as Map<String, dynamic>;
          if (json['missing'] == true || json['invalid'] == true) return null;
          final model = PersonalEegModel.fromJson(json);
          if (model.ownerAccountId != owner || model.origin != origin.name) {
            return null;
          }
          if (!await _evidenceCurrent(owner, model)) {
            return PersonalEegModel.fromJson({
              ...model.toJson(),
              'status': 'revoked',
              'reasons': ['Included evidence was deleted or changed'],
            });
          }
          return model;
        } on FormatException {
          return null;
        } on TypeError {
          return null;
        }
      });
  Future<bool> refresh(
    String owner,
    DataOrigin origin, {
    required bool Function() isCurrent,
  }) async {
    final generation = api.authGeneration;
    bool current() =>
        isCurrent() &&
        api.accountId == owner &&
        api.authGeneration == generation;
    if (!current()) return false;
    final epoch = await sessions.readEvidenceEpoch(owner);
    final previousCache = await db.getKv(_key(owner, origin));
    if (!current()) return false;
    PersonalEegModel? model;
    bool invalid = false;
    try {
      model = await api.latestMeditationModel(origin);
    } on FormatException {
      invalid = true;
    } on TypeError {
      invalid = true;
    } on StateError {
      if (!current()) return false;
      rethrow;
    }
    if (!current()) return false;
    if (model != null &&
        (model.ownerAccountId != owner || model.origin != origin.name)) {
      invalid = true;
      model = null;
    }
    try {
      return await db.transaction(() async {
        if (!current()) return false;
        // Another refresh/deletion may have committed while HTTP was held.
        // Compare durable state, including across repository instances.
        if (await db.getKv(_key(owner, origin)) != previousCache) return false;
        final valid = model == null || await _evidenceCurrent(owner, model);
        final value = valid && model != null
            ? model.toJson()
            : {
                'missing': !invalid && model == null,
                'invalid': invalid || !valid,
              };
        final published = await sessions.publishEvidenceCache(
          owner,
          expectedLocalEpoch: epoch,
          includedSessionIds: model?.includedSessionIds ?? [],
          key: _key(owner, origin),
          value: jsonEncode(value),
          isCurrent: current,
        );
        if (!published) return false;
        await retireSupersededMeditationStatistics(
          db,
          owner,
          origin.name,
          valid && model?.status == 'ready' ? model!.modelVersion : null,
        );
        if (!current()) throw const _ModelPublicationCancelled();
        return true;
      });
    } on _ModelPublicationCancelled {
      return false;
    }
  }
}

class _ModelPublicationCancelled implements Exception {
  const _ModelPublicationCancelled();
}
