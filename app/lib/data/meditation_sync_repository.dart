import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:drift/drift.dart';
import 'package:neurotune_core/neurotune_core.dart';
import 'database.dart';
import 'repository.dart';

bool isMeditation(SessionManifest m) =>
    m.meditation != null ||
    m.mode == 'meditation' ||
    m.experimentVersion == MeditationProtocol.protocolVersion;

String? meditationOwner(SessionManifest m) {
  final meta = m.meditation;
  final profile = meta?['profile'];
  if (profile is! Map) return null;
  final owner = profile['owner_account_id'];
  return owner is String &&
          isAccountUuid(owner) &&
          (meta?['owner_account_id'] == null ||
              meta?['owner_account_id'] == owner)
      ? owner
      : null;
}

class MeditationSyncStatus {
  const MeditationSyncStatus(this.pending, this.errors, this.synced);
  final int pending, errors, synced;
}

/// Mutable delivery state only. Neither feedback edits nor acknowledgements
/// rewrite a recording, its raw file or checksum.
class MeditationSyncRepository {
  MeditationSyncRepository(this.db);
  final AppDatabase db;

  Future<List<StoredCalibrationPlan>> plans(String owner) =>
      (db.select(db.calibrationPlans)..where(
            (r) =>
                r.ownerAccountId.equals(owner) & r.syncState.equals('pending'),
          ))
          .get();
  Future<bool> planAccepted(String owner, String id) async =>
      (await (db.select(db.calibrationPlans)..where(
            (r) =>
                r.ownerAccountId.equals(owner) &
                r.id.equals(id) &
                r.syncState.equals('done'),
          ))
          .getSingleOrNull()) !=
      null;
  Future<void> markPlan(StoredCalibrationPlan row, {String? error}) async =>
      (db.update(db.calibrationPlans)..where(
            (r) =>
                r.ownerAccountId.equals(row.ownerAccountId) &
                r.id.equals(row.id) &
                r.syncState.equals('pending'),
          ))
          .write(
            CalibrationPlansCompanion(
              syncState: Value(error == null ? 'done' : 'pending'),
              attempts: Value(row.attempts + (error == null ? 0 : 1)),
              lastError: Value(error),
            ),
          );

  Future<List<MeditationFeedbackRow>> feedback(String owner) =>
      (db.select(db.meditationFeedbackRows)..where(
            (r) =>
                r.ownerAccountId.equals(owner) &
                r.syncState.equals('pending') &
                r.mentalBusyness.isNotNull() &
                r.relaxation.isNotNull(),
          ))
          .get();
  MeditationFeedback outcome(MeditationFeedbackRow row) => MeditationFeedback(
    ownerAccountId: row.ownerAccountId,
    sessionId: row.sessionId,
    mentalBusyness: row.mentalBusyness,
    relaxation: row.relaxation,
    revision: row.revision,
  );
  Future<bool> rawAccepted(String sid, String email) async =>
      (await (db.select(db.uploadJobs)..where(
            (r) =>
                r.sessionId.equals(sid) &
                r.ownerEmail.equals(email) &
                r.state.equals('done'),
          ))
          .getSingleOrNull()) !=
      null;

  Future<void> acknowledgeFeedback(
    MeditationFeedbackRow row,
    SavedSession session,
  ) => db.transaction(() async {
    // A deletion or edit while the response was in flight cannot be acknowledged.
    final saved = await (db.select(
      db.storedSessions,
    )..where((r) => r.id.equals(row.sessionId))).getSingleOrNull();
    if (saved == null) return;
    final changed =
        await (db.update(db.meditationFeedbackRows)..where(
              (r) =>
                  r.ownerAccountId.equals(row.ownerAccountId) &
                  r.sessionId.equals(row.sessionId) &
                  r.revision.equals(row.revision) &
                  r.syncState.equals('pending'),
            ))
            .write(
              const MeditationFeedbackRowsCompanion(
                syncState: Value('done'),
                lastError: Value(null),
              ),
            );
    if (changed == 0 ||
        ![
          'fixed',
          'calibration',
        ].contains(session.manifest.meditation?['mode'])) {
      return;
    }
    final request = newSessionId(Random.secure());
    await db
        .into(db.meditationTrainingOutbox)
        .insert(
          MeditationTrainingOutboxCompanion.insert(
            ownerAccountId: row.ownerAccountId,
            sessionId: row.sessionId,
            feedbackRevision: row.revision,
            requestId: request,
            bodyJson: jsonEncode({
              'schema_version': 1,
              'request_id': request,
              'session_id': row.sessionId,
              'feedback_revision': row.revision,
              'origin': session.origin,
              'protocol_version':
                  session.manifest.meditation!['protocol_version'],
            }),
          ),
          mode: InsertMode.insertOrIgnore,
        );
  });

  Future<void> failFeedback(
    MeditationFeedbackRow row,
    Object error, {
    bool gone = false,
  }) async =>
      (db.update(db.meditationFeedbackRows)..where(
            (r) =>
                r.ownerAccountId.equals(row.ownerAccountId) &
                r.sessionId.equals(row.sessionId) &
                r.revision.equals(row.revision) &
                r.syncState.equals('pending'),
          ))
          .write(
            MeditationFeedbackRowsCompanion(
              syncState: Value(gone ? 'deleted' : 'pending'),
              attempts: Value(row.attempts + 1),
              lastError: Value('$error'),
            ),
          );
  Future<List<MeditationTrainingOutboxData>> training(String owner) =>
      (db.select(db.meditationTrainingOutbox)..where(
            (r) =>
                r.ownerAccountId.equals(owner) & r.syncState.equals('pending'),
          ))
          .get();
  Future<bool> trainingCurrent(MeditationTrainingOutboxData row) async {
    final feedback =
        await (db.select(db.meditationFeedbackRows)..where(
              (r) =>
                  r.ownerAccountId.equals(row.ownerAccountId) &
                  r.sessionId.equals(row.sessionId) &
                  r.revision.equals(row.feedbackRevision) &
                  r.syncState.equals('done'),
            ))
            .getSingleOrNull();
    return feedback != null;
  }

  Future<void> markTraining(
    MeditationTrainingOutboxData row,
    String state, {
    Object? error,
  }) async =>
      (db.update(db.meditationTrainingOutbox)..where(
            (r) =>
                r.ownerAccountId.equals(row.ownerAccountId) &
                r.sessionId.equals(row.sessionId) &
                r.feedbackRevision.equals(row.feedbackRevision) &
                r.syncState.equals('pending'),
          ))
          .write(
            MeditationTrainingOutboxCompanion(
              syncState: Value(state),
              attempts: Value(row.attempts + (error == null ? 0 : 1)),
              lastError: Value(error == null ? null : '$error'),
            ),
          );

  Future<void> retireDeletedSession(
    String owner,
    String sessionId,
  ) => db.transaction(() async {
    await (db.update(db.meditationFeedbackRows)..where(
          (r) => r.ownerAccountId.equals(owner) & r.sessionId.equals(sessionId),
        ))
        .write(
          const MeditationFeedbackRowsCompanion(
            syncState: Value('deleted'),
            lastError: Value(null),
          ),
        );
    await (db.update(db.meditationTrainingOutbox)..where(
          (r) => r.ownerAccountId.equals(owner) & r.sessionId.equals(sessionId),
        ))
        .write(
          const MeditationTrainingOutboxCompanion(
            syncState: Value('deleted'),
            lastError: Value(null),
          ),
        );
  });

  Stream<MeditationSyncStatus> watchStatus(String owner, String email) =>
      Stream.multi((controller) {
        var disposed = false;
        var revision = 0;
        final query = db.customSelect(
          '''
    SELECT state, error FROM (
      SELECT sync_state AS state, last_error AS error FROM calibration_plans WHERE owner_account_id = ?
      UNION ALL SELECT sync_state, last_error FROM meditation_feedback_rows WHERE owner_account_id = ? AND mental_busyness IS NOT NULL AND relaxation IS NOT NULL
      UNION ALL SELECT sync_state, last_error FROM meditation_training_outbox WHERE owner_account_id = ?
      UNION ALL SELECT state, last_error FROM upload_jobs WHERE owner_email = ?
    )
    ''',
          variables: [
            Variable(owner),
            Variable(owner),
            Variable(owner),
            Variable(email.toLowerCase()),
          ],
          readsFrom: {
            db.calibrationPlans,
            db.meditationFeedbackRows,
            db.meditationTrainingOutbox,
            db.uploadJobs,
          },
        );
        void refresh() {
          final requested = ++revision;
          unawaited(
            query.get().then(
              (rows) {
                if (!disposed && requested == revision) {
                  final pending = rows.where(
                    (row) => [
                      'pending',
                      'delete_pending',
                      'conflict',
                    ].contains(row.read<String>('state')),
                  );
                  controller.add(
                    MeditationSyncStatus(
                      pending.length,
                      pending
                          .where(
                            (row) => row.readNullable<String>('error') != null,
                          )
                          .length,
                      rows
                          .where((row) => row.read<String>('state') == 'done')
                          .length,
                    ),
                  );
                }
              },
              onError: (Object error, StackTrace stack) {
                if (!disposed) controller.addError(error, stack);
              },
            ),
          );
        }

        // Table notifications have no query-cache disposal delay. Cancel them
        // immediately when account/navigation removes the status widget.
        final updates = db
            .tableUpdates(
              TableUpdateQuery.onAllTables([
                db.calibrationPlans,
                db.meditationFeedbackRows,
                db.meditationTrainingOutbox,
                db.uploadJobs,
              ]),
            )
            .listen((_) => refresh());
        controller.onCancel = () {
          disposed = true;
          return updates.cancel();
        };
        refresh();
      });
}
