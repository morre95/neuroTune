import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:neurotune_core/neurotune_core.dart' hide UploadJob;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'database.dart';
import 'meditation_sync_repository.dart';
import 'meditation_learning_cleanup.dart';

class PendingUpload {
  PendingUpload({
    required this.sessionId,
    required this.ownerEmail,
    required this.checksum,
    required this.payloadPath,
    required this.attempts,
  });
  final String sessionId;
  final String? ownerEmail;
  final String checksum;
  final String payloadPath;
  final int attempts;
}

class SavedSession {
  SavedSession({
    required this.id,
    required this.origin,
    required this.mode,
    required this.manifest,
    required this.decisions,
    required this.frames,
    required this.status,
    required this.checksum,
    required this.createdAt,
  });

  final String id;
  final String origin;
  final String mode;
  final SessionManifest manifest;
  final List<DecisionEvent> decisions;
  final List<FeatureFrame> frames;
  final String status;
  final String checksum;
  final DateTime createdAt;
}

class SessionRepository {
  SessionRepository(this.db);
  final AppDatabase db;

  String _epochKey(String owner) {
    if (!isAccountUuid(owner)) {
      throw ArgumentError('Owned account UUID required');
    }
    return 'meditation_evidence_epoch:v1:$owner';
  }

  Future<int> readEvidenceEpoch(String owner) async {
    final value = await db.getKv(_epochKey(owner));
    if (value == null) return 0;
    final epoch = int.tryParse(value);
    if (epoch == null || epoch < 0) throw StateError('Invalid evidence epoch');
    return epoch;
  }

  Future<int> bumpEvidenceEpoch(String owner) => db.transaction(() async {
    final next = await readEvidenceEpoch(owner) + 1;
    await db.putKv(_epochKey(owner), '$next');
    return next;
  });

  Future<bool> isTombstoned(String owner, String sessionId) async =>
      (await (db.select(db.sessionTombstones)..where(
            (r) =>
                r.ownerAccountId.equals(owner) & r.sessionId.equals(sessionId),
          ))
          .getSingleOrNull()) !=
      null;

  Future<void> _rejectDeleted(String sessionId) async {
    if (await (db.select(
          db.sessionTombstones,
        )..where((r) => r.sessionId.equals(sessionId))).getSingleOrNull() !=
        null) {
      throw StateError('Sessionen är raderad.');
    }
  }

  Future<bool> publishEvidenceCache(
    String owner, {
    required int expectedLocalEpoch,
    required Iterable<String> includedSessionIds,
    required String key,
    required String value,
    bool Function()? isCurrent,
  }) async {
    _epochKey(owner);
    final parts = key.split(':');
    if (parts.length < 4 ||
        parts[2] != owner ||
        !['meditation_model', 'meditation_action_stats'].contains(parts[0])) {
      throw ArgumentError('Owned evidence cache namespace required');
    }
    bool current() => isCurrent?.call() ?? true;
    try {
      return await db.transaction(() async {
        if (!current() ||
            await readEvidenceEpoch(owner) != expectedLocalEpoch) {
          return false;
        }
        for (final id in includedSessionIds) {
          if (await isTombstoned(owner, id)) return false;
        }
        if (!current()) return false;
        await db.putKv(key, value);
        if (!current()) throw const _EvidencePublicationCancelled();
        return true;
      });
    } on _EvidencePublicationCancelled {
      return false;
    }
  }

  Future<void> saveConfig(ExperimentConfig config) =>
      db.putKv('config', jsonEncode(config.toJson()));

  Future<ExperimentConfig> loadConfig() async {
    final raw = await db.getKv('config');
    if (raw == null) return ExperimentConfig.defaults();
    return ExperimentConfig.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    ).forCurrentProcessing();
  }

  /// Logins were kept in the database before they moved to encrypted storage.
  Future<String?> loadLegacyAuth() => db.getKv('auth');

  Future<void> deleteLegacyAuth() => db.deleteKv('auth');

  Future<void> saveBandit(BanditSnapshot snapshot) =>
      db.putKv('bandit:${snapshot.dataOrigin}', jsonEncode(snapshot.toJson()));

  Future<BanditSnapshot?> loadBandit(String origin) async {
    final raw = await db.getKv('bandit:$origin');
    if (raw == null) return null;
    return BanditSnapshot.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<String> saveSession({
    required SessionManifest manifest,
    required List<DecisionEvent> decisions,
    required List<FeatureFrame> frames,
    required List<int> raw,
    required String checksum,
    required String status,
  }) => db.transaction(() async {
    await _rejectDeleted(manifest.sessionId);
    final directory = await getApplicationDocumentsDirectory();
    final folder = Directory(p.join(directory.path, 'sessions'));
    await folder.create(recursive: true);
    final rawPath = p.join(folder.path, '${manifest.sessionId}.bin');
    await File(rawPath).writeAsBytes(raw);
    await db
        .into(db.storedSessions)
        .insertOnConflictUpdate(
          StoredSessionsCompanion.insert(
            id: manifest.sessionId,
            origin: manifest.dataOrigin,
            mode: manifest.mode,
            manifestJson: jsonEncode(manifest.toJson()),
            decisionsJson: jsonEncode([
              for (final decision in decisions) decision.toJson(),
            ]),
            framesJson: jsonEncode([
              for (final frame in frames) frame.toJson(),
            ]),
            status: status,
            checksum: checksum,
            rawPath: rawPath,
            createdAt: DateTime.now().toUtc(),
          ),
        );
    final owner = meditationOwner(manifest);
    if (owner != null &&
        ['fixed', 'calibration'].contains(manifest.meditation?['mode'])) {
      await bumpEvidenceEpoch(owner);
    }
    return rawPath;
  });

  Future<List<SavedSession>> listSessions() async {
    final rows = await (db.select(
      db.storedSessions,
    )..orderBy([(table) => OrderingTerm.desc(table.createdAt)])).get();
    return rows.map(_saved).toList();
  }

  /// Only the account which owns the upload may request remote deletion.
  Future<List<SavedSession>> listOwnedSessions(String ownerEmail) async {
    final jobs = await (db.select(
      db.uploadJobs,
    )..where((row) => row.ownerEmail.equals(ownerEmail.toLowerCase()))).get();
    final ids = jobs.map((job) => job.sessionId).toSet();
    return (await listSessions())
        .where((session) => ids.contains(session.id))
        .toList();
  }

  /// Queue remote deletion in the same transaction that hides local sessions.
  /// Retain the raw path until cleanup succeeds, including across app restarts.
  Future<void> deleteSessions(
    List<String> sessionIds,
    String ownerEmail, {
    String? ownerAccountId,
    bool Function()? isCurrent,
    bool cleanupRaw = true,
  }) async {
    final ids = sessionIds.toSet().toList();
    if (ids.isEmpty) return;
    final email = ownerEmail.toLowerCase();
    bool current() => isCurrent?.call() ?? true;
    await db.transaction(() async {
      if (!current()) throw StateError('Account changed');
      final jobs = {
        for (final row in await (db.select(
          db.uploadJobs,
        )..where((r) => r.sessionId.isIn(ids))).get())
          row.sessionId: row,
      };
      final markers = {
        for (final row in await (db.select(
          db.sessionTombstones,
        )..where((r) => r.sessionId.isIn(ids))).get())
          row.sessionId: row,
      };
      final saved = {
        for (final row in await (db.select(
          db.storedSessions,
        )..where((r) => r.id.isIn(ids))).get())
          row.id: row,
      };
      final changedOwners = <String>{};
      final retiredByOwner = <String, Set<String>>{};
      for (final id in ids) {
        final job = jobs[id], marker = markers[id];
        if ((job == null && marker == null) ||
            (job != null && job.ownerEmail != email) ||
            (marker != null &&
                (marker.ownerEmail != email ||
                    (ownerAccountId != null &&
                        marker.ownerAccountId != null &&
                        marker.ownerAccountId != ownerAccountId)))) {
          throw StateError(
            'Du kan bara radera sessioner som tillhör ditt konto.',
          );
        }
        final manifest = saved[id] == null ? null : _saved(saved[id]!).manifest;
        final uuid = manifest == null
            ? marker?.ownerAccountId ?? ownerAccountId
            : meditationOwner(manifest) ?? ownerAccountId;
        if (ownerAccountId != null && uuid != null && uuid != ownerAccountId) {
          throw StateError('Sessionen tillhör ett annat konto.');
        }
        if (marker == null) {
          await db
              .into(db.sessionTombstones)
              .insert(
                SessionTombstonesCompanion.insert(
                  sessionId: id,
                  ownerEmail: email,
                  ownerAccountId: Value(uuid),
                  createdAt: DateTime.now().toUtc(),
                ),
              );
          if (uuid != null && manifest != null && isMeditation(manifest)) {
            changedOwners.add(uuid);
          }
        }
        if (job != null && job.state != 'delete_pending') {
          await (db.update(
            db.uploadJobs,
          )..where((r) => r.sessionId.equals(id))).write(
            const UploadJobsCompanion(
              state: Value('delete_pending'),
              attempts: Value(0),
              lastError: Value(null),
            ),
          );
        }
        if (uuid != null) {
          retiredByOwner.putIfAbsent(uuid, () => {}).add(id);
          await (db.delete(db.meditationFeedbackRows)..where(
                (r) => r.ownerAccountId.equals(uuid) & r.sessionId.equals(id),
              ))
              .go();
          await (db.delete(db.calibrationAttempts)..where(
                (r) => r.ownerAccountId.equals(uuid) & r.sessionId.equals(id),
              ))
              .go();
          await (db.delete(db.meditationTrainingOutbox)..where(
                (r) => r.ownerAccountId.equals(uuid) & r.sessionId.equals(id),
              ))
              .go();
        }
      }
      await (db.delete(db.storedSessions)..where((r) => r.id.isIn(ids))).go();
      for (final entry in retiredByOwner.entries) {
        await retireMeditationLearning(db, entry.key, entry.value);
      }
      for (final owner in changedOwners) {
        await bumpEvidenceEpoch(owner);
      }
      await (db.delete(db.kvStore)..where((r) => r.key.like('bandit:%'))).go();
      if (!current()) throw StateError('Account changed');
    });
    if (!cleanupRaw) return;
    for (final job in await pendingDeletions(email)) {
      if (ids.contains(job.sessionId)) {
        try {
          await _deleteRawFile(job.payloadPath);
        } on FileSystemException {
          // The durable queue retains the path until cleanup succeeds.
        }
      }
    }
  }

  /// Only persist the evidence retirement here. The sync caller commits its
  /// generation-guarded transaction before irreversible raw cleanup starts.
  Future<void> recordServerDeletion(
    String sessionId,
    String ownerEmail,
    String ownerAccountId, {
    required bool Function() isCurrent,
  }) => deleteSessions(
    [sessionId],
    ownerEmail,
    ownerAccountId: ownerAccountId,
    isCurrent: isCurrent,
    cleanupRaw: false,
  );

  /// Authoritative owned tombstones discovered during idle learning sync.
  /// Evidence can have come from another phone, so unknown local IDs also need
  /// durable markers. Foreign/legacy local recordings remain untouched.
  Future<List<String>> recordServerDeletions(
    Iterable<String> sessionIds,
    String ownerEmail,
    String owner, {
    required bool Function() isCurrent,
  }) => db.transaction(() async {
    _epochKey(owner);
    if (!isCurrent()) throw StateError('Account changed');
    final before = await readEvidenceEpoch(owner);
    final known = <String>[], absent = <String>{};
    bool added = false;
    for (final id in sessionIds.toSet()) {
      final marker = await (db.select(
        db.sessionTombstones,
      )..where((r) => r.sessionId.equals(id))).getSingleOrNull();
      if (marker != null && marker.ownerAccountId != owner) continue;
      final row = await (db.select(
        db.storedSessions,
      )..where((r) => r.id.equals(id))).getSingleOrNull();
      if (row != null && meditationOwner(_saved(row).manifest) != owner) {
        continue;
      }
      final job = await (db.select(
        db.uploadJobs,
      )..where((r) => r.sessionId.equals(id))).getSingleOrNull();
      if (job != null && job.ownerEmail != ownerEmail.toLowerCase()) continue;
      if (row != null || marker != null || job != null) {
        known.add(id);
      } else {
        await db
            .into(db.sessionTombstones)
            .insert(
              SessionTombstonesCompanion.insert(
                sessionId: id,
                ownerEmail: ownerEmail.toLowerCase(),
                ownerAccountId: Value(owner),
                createdAt: DateTime.now().toUtc(),
              ),
            );
        absent.add(id);
        added = true;
        await (db.delete(db.meditationFeedbackRows)..where(
              (r) => r.ownerAccountId.equals(owner) & r.sessionId.equals(id),
            ))
            .go();
        await (db.delete(db.calibrationAttempts)..where(
              (r) => r.ownerAccountId.equals(owner) & r.sessionId.equals(id),
            ))
            .go();
        await (db.delete(db.meditationTrainingOutbox)..where(
              (r) => r.ownerAccountId.equals(owner) & r.sessionId.equals(id),
            ))
            .go();
      }
    }
    if (known.isNotEmpty) {
      await deleteSessions(
        known,
        ownerEmail,
        ownerAccountId: owner,
        isCurrent: isCurrent,
        cleanupRaw: false,
      );
    }
    if (absent.isNotEmpty) await retireMeditationLearning(db, owner, absent);
    if (added && await readEvidenceEpoch(owner) == before) {
      await bumpEvidenceEpoch(owner);
    }
    if (!isCurrent()) throw StateError('Account changed');
    return [...known, ...absent];
  });

  Future<List<PendingUpload>> pendingDeletions(
    String ownerEmail, {
    String? ownerAccountId,
  }) async {
    final rows =
        await (db.select(db.uploadJobs)..where(
              (row) =>
                  row.state.equals('delete_pending') &
                  row.ownerEmail.equals(ownerEmail.toLowerCase()),
            ))
            .get();
    final markers = ownerAccountId == null
        ? <String, SessionTombstone>{}
        : {
            for (final marker
                in await (db.select(db.sessionTombstones)..where(
                      (r) => r.sessionId.isIn(rows.map((row) => row.sessionId)),
                    ))
                    .get())
              marker.sessionId: marker,
          };
    return [
      for (final row in rows)
        if (markers[row.sessionId]?.ownerAccountId == null ||
            markers[row.sessionId]?.ownerAccountId == ownerAccountId)
          PendingUpload(
            sessionId: row.sessionId,
            ownerEmail: row.ownerEmail,
            checksum: row.checksum,
            payloadPath: row.payloadPath,
            attempts: row.attempts,
          ),
    ];
  }

  /// Call after evidence retirement has committed. A cancelled acknowledgement
  /// may retain the queue, but must never restore evidence whose raw was unlinked.
  Future<void> completeDeletion(
    PendingUpload job, {
    bool Function()? isCurrent,
  }) async {
    bool current() => isCurrent?.call() ?? true;
    if (!current()) throw StateError('Delivery cancelled');
    await _deleteRawFile(job.payloadPath);
    await db.transaction(() async {
      if (!current()) throw StateError('Delivery cancelled');
      await (db.delete(db.uploadJobs)..where(
            (row) =>
                row.sessionId.equals(job.sessionId) &
                row.state.equals('delete_pending') &
                row.ownerEmail.equals(job.ownerEmail!),
          ))
          .go();
      // A restart could have fetched an old policy before deletion synced.
      await (db.delete(
        db.kvStore,
      )..where((row) => row.key.like('bandit:%'))).go();
      if (!current()) throw StateError('Delivery cancelled');
    });
  }

  Future<void> _deleteRawFile(String path) async {
    try {
      await File(path).delete();
    } on FileSystemException catch (error) {
      if (error.osError?.errorCode != 2) rethrow;
    }
  }

  Future<List<LocalSessionRewards>> localRewards(
    String origin,
    String experimentVersion,
  ) async {
    final sessions = await listSessions();
    return [
      for (final session in sessions)
        if (!isMeditation(session.manifest) &&
            session.origin == origin &&
            session.manifest.experimentVersion == experimentVersion)
          LocalSessionRewards(
            sessionId: session.id,
            origin: DataOrigin.values.byName(session.origin),
            experimentVersion: experimentVersion,
            personal: session.mode == SessionMode.personal.name,
            rewards: [
              for (final decision in session.decisions)
                if (decision.updatedBandit && decision.reward != null)
                  LocalReward(
                    StimulusAction.byId(decision.action),
                    decision.reward!,
                  ),
            ],
          ),
    ];
  }

  Future<void> enqueueUpload(
    String sessionId,
    String checksum,
    String rawPath,
    String ownerEmail,
  ) => db.transaction(() async {
    await _rejectDeleted(sessionId);
    await db
        .into(db.uploadJobs)
        .insertOnConflictUpdate(
          UploadJobsCompanion.insert(
            sessionId: sessionId,
            ownerEmail: Value(ownerEmail.toLowerCase()),
            checksum: checksum,
            payloadPath: rawPath,
            state: 'pending',
          ),
        );
  });

  Future<List<PendingUpload>> pendingUploads() async {
    final rows = await (db.select(
      db.uploadJobs,
    )..where((table) => table.state.equals('pending'))).get();
    return [
      for (final row in rows)
        PendingUpload(
          sessionId: row.sessionId,
          ownerEmail: row.ownerEmail,
          checksum: row.checksum,
          payloadPath: row.payloadPath,
          attempts: row.attempts,
        ),
    ];
  }

  Future<void> claimLegacyUploads(String ownerEmail) async {
    final hasSessions =
        (await db
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type='table' AND name='stored_sessions'",
                )
                .get())
            .isNotEmpty;
    final meditationIds = hasSessions
        ? (await listSessions())
              .where((s) => isMeditation(s.manifest))
              .map((s) => s.id)
              .toList()
        : <String>[];
    await (db.update(db.uploadJobs)..where(
          (r) => r.ownerEmail.isNull() & r.sessionId.isNotIn(meditationIds),
        ))
        .write(
          UploadJobsCompanion(ownerEmail: Value(ownerEmail.toLowerCase())),
        );
  }

  Future<void> markUpload(
    String sessionId,
    String state, {
    int? attempts,
    String? error,
  }) {
    return (db.update(db.uploadJobs)..where(
          (table) =>
              table.sessionId.equals(sessionId) &
              table.state.equals(
                state == 'delete_pending' ? 'delete_pending' : 'pending',
              ),
        ))
        .write(
          UploadJobsCompanion(
            state: Value(state),
            attempts: attempts == null ? const Value.absent() : Value(attempts),
            lastError: Value(error),
          ),
        );
  }

  SavedSession _saved(StoredSession row) {
    return SavedSession(
      id: row.id,
      origin: row.origin,
      mode: row.mode,
      manifest: SessionManifest.fromJson(
        jsonDecode(row.manifestJson) as Map<String, dynamic>,
      ),
      decisions: [
        for (final item in jsonDecode(row.decisionsJson) as List<dynamic>)
          DecisionEvent.fromJson(item as Map<String, dynamic>),
      ],
      frames: [
        for (final item in jsonDecode(row.framesJson) as List<dynamic>)
          FeatureFrame.fromJson(item as Map<String, dynamic>),
      ],
      status: row.status,
      checksum: row.checksum,
      createdAt: row.createdAt,
    );
  }
}

class _EvidencePublicationCancelled implements Exception {
  const _EvidencePublicationCancelled();
}
