import 'dart:convert';
import 'dart:math';
import 'package:drift/drift.dart';
import 'package:neurotune_core/neurotune_core.dart';
import 'database.dart';
import 'repository.dart';

class CalibrationAttemptView {
  const CalibrationAttemptView(this.sessionId, this.slot, this.status);
  final String sessionId;
  final int slot;
  final String status;
}

class CalibrationProgress {
  const CalibrationProgress(
    this.plan,
    this.attempts,
    this.results,
    this.awaitingFeedback,
  );
  final CalibrationPlan plan;
  final List<CalibrationAttemptView> attempts;
  final Map<int, SessionSummary> results;
  final List<SessionSummary> awaitingFeedback;
  int get completedSlots => results.length;
  bool get complete => completedSlots == 10;
  int? get nextSlot {
    for (var slot = 0; slot < 10; slot++) {
      if (!results.containsKey(slot)) return slot;
    }
    return null;
  }
}

/// Account-owned comparisons and mutable feedback; recordings remain immutable.
class CalibrationRepository {
  CalibrationRepository(this.db, this.sessions);
  final AppDatabase db;
  final SessionRepository sessions;

  Future<CalibrationPlan> createPlan({
    required String ownerAccountId,
    required AudioProfileVersion profile,
    required EyeState eyeState,
    required DataOrigin origin,
    Random? random,
  }) async {
    final rng = random ?? Random.secure();
    final plan = CalibrationPlan(
      id: newSessionId(rng),
      ownerAccountId: ownerAccountId,
      profile: profile,
      eyeState: eyeState,
      origin: origin,
      schedule: CalibrationPlan.shuffled(rng),
      createdAt: DateTime.now().toUtc(),
    );
    await db
        .into(db.calibrationPlans)
        .insert(
          CalibrationPlansCompanion.insert(
            ownerAccountId: ownerAccountId,
            id: plan.id,
            bodyJson: jsonEncode(plan.toJson()),
          ),
        );
    return plan;
  }

  Future<List<CalibrationPlan>> plans(String owner) async {
    final rows = await (db.select(
      db.calibrationPlans,
    )..where((r) => r.ownerAccountId.equals(owner))).get();
    return rows
        .map(
          (r) => CalibrationPlan.fromJson(
            jsonDecode(r.bodyJson) as Map<String, dynamic>,
          ),
        )
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<CalibrationPlan> plan(String owner, String id) async {
    final row =
        await (db.select(db.calibrationPlans)
              ..where((r) => r.ownerAccountId.equals(owner) & r.id.equals(id)))
            .getSingleOrNull();
    if (row == null) throw StateError('Kalibreringen tillhör inte ditt konto.');
    return CalibrationPlan.fromJson(
      jsonDecode(row.bodyJson) as Map<String, dynamic>,
    );
  }

  Future<List<CalibrationProgress>> allProgress(String owner) async =>
      (await snapshot(owner)).progress;

  /// One consistent metadata snapshot, shared by progress and pending feedback.
  Future<CalibrationState> snapshot(String owner, {String? planId}) =>
      db.transaction(() async {
        final ownedPlans = planId == null
            ? await plans(owner)
            : [await plan(owner, planId)];
        final rows =
            await (db.select(db.calibrationAttempts)
                  ..where(
                    (r) =>
                        r.ownerAccountId.equals(owner) &
                        (planId == null
                            ? const Constant(true)
                            : r.planId.equals(planId)),
                  )
                  ..orderBy([(r) => OrderingTerm.asc(r.createdAt)]))
                .get();
        final saved = {
          for (final s
              in planId == null
                  ? await sessions.meditationSummaries(owner)
                  : await sessions.summariesByIds(rows.map((r) => r.sessionId)))
            s.id: s,
        };
        final ratings = await feedbackBySession(owner);
        final byPlan = <String, List<CalibrationAttempt>>{};
        for (final row in rows) {
          byPlan.putIfAbsent(row.planId, () => []).add(row);
        }
        final progress = [
          for (final p in ownedPlans)
            _progress(p, byPlan[p.id] ?? [], saved, ratings),
        ];
        final pending = [for (final p in progress) ...p.awaitingFeedback];
        if (planId == null) {
          for (final s in saved.values) {
            if (s.manifest.meditation?['mode'] != 'calibration' &&
                _ownedCompleted(s, owner) &&
                ratings[s.id]?.complete != true) {
              pending.add(s);
            }
          }
        }
        return CalibrationState(progress, pending);
      });

  Future<Map<String, MeditationFeedback>> feedbackBySession(
    String owner,
  ) async {
    final rows = await (db.select(
      db.meditationFeedbackRows,
    )..where((r) => r.ownerAccountId.equals(owner))).get();
    return {
      for (final r in rows)
        r.sessionId: MeditationFeedback(
          ownerAccountId: owner,
          sessionId: r.sessionId,
          mentalBusyness: r.mentalBusyness,
          relaxation: r.relaxation,
          revision: r.revision,
        ),
    };
  }

  bool _matchesProfile(Object? snapshot, AudioProfileVersion expected) {
    if (snapshot is! Map) return false;
    try {
      final actual = AudioProfileVersion.fromJson(
        Map<String, dynamic>.from(snapshot),
      );
      return actual.id == expected.id &&
          actual.ownerAccountId == expected.ownerAccountId &&
          actual.profileId == expected.profileId &&
          actual.version == expected.version &&
          actual.backgroundAssetId == expected.backgroundAssetId &&
          actual.checksumSha256 == expected.checksumSha256 &&
          actual.carrierHz == expected.carrierHz &&
          actual.toneGain == expected.toneGain &&
          actual.backgroundGain == expected.backgroundGain &&
          actual.durationSeconds == expected.durationSeconds &&
          actual.loop == expected.loop;
    } on FormatException {
      return false;
    } on TypeError {
      return false;
    }
  }

  bool _ownedCompleted(SessionSummary session, String owner) {
    final m = session.manifest;
    final meta = m.meditation;
    if (session.status != 'completed' ||
        m.durationSeconds != 600 ||
        m.stopReason != null ||
        m.endedInPhase != 'completed' ||
        meta?['schema_version'] != 1 ||
        meta?['protocol_version'] != MeditationProtocol.protocolVersion ||
        meta?['played_frames'] != MeditationProtocol.totalFrames ||
        meta?['profile'] is! Map ||
        !['fixed', 'calibration', 'adaptive'].contains(meta?['mode'])) {
      return false;
    }
    try {
      final profile = AudioProfileVersion.fromJson(
        Map<String, dynamic>.from(meta!['profile'] as Map),
      );
      return profile.ownerAccountId == owner &&
          (meta['owner_account_id'] == null ||
              meta['owner_account_id'] == owner) &&
          meta['profile_version_id'] == profile.id &&
          meta['origin'] == m.dataOrigin &&
          meta['eye_state'] == m.eyeState;
    } on FormatException {
      return false;
    } on TypeError {
      return false;
    }
  }

  bool _completed(SessionSummary session, CalibrationPlan plan, int slot) {
    final m = session.manifest;
    final meta = m.meditation;
    return _ownedCompleted(session, plan.ownerAccountId) &&
        session.status == 'completed' &&
        m.durationSeconds == 600 &&
        m.stopReason == null &&
        m.endedInPhase == 'completed' &&
        meta?['schema_version'] == 1 &&
        meta?['protocol_version'] == MeditationProtocol.protocolVersion &&
        _matchesProfile(meta?['profile'], plan.profile) &&
        meta?['played_frames'] == MeditationProtocol.totalFrames &&
        meta?['calibration_plan_id'] == plan.id &&
        meta?['calibration_slot'] == slot &&
        meta?['owner_account_id'] == plan.ownerAccountId &&
        meta?['mode'] == 'calibration' &&
        meta?['fixed_action'] == plan.schedule[slot].id &&
        meta?['profile_version_id'] == plan.profile.id &&
        m.eyeState == plan.eyeState.name &&
        m.dataOrigin == plan.origin.name;
  }

  Future<CalibrationProgress> progress(String owner, String id) async =>
      (await snapshot(owner, planId: id)).progress.single;

  CalibrationProgress _progress(
    CalibrationPlan p,
    List<CalibrationAttempt> rows,
    Map<String, SessionSummary> saved,
    Map<String, MeditationFeedback> ratings,
  ) {
    final results = <int, SessionSummary>{};
    final awaiting = <SessionSummary>[];
    final attempts = <CalibrationAttemptView>[];
    for (final row in rows) {
      final s = saved[row.sessionId];
      final full = s != null && _completed(s, p, row.slot);
      final rated = full && ratings[row.sessionId]?.complete == true;
      attempts.add(
        CalibrationAttemptView(
          row.sessionId,
          row.slot,
          rated
              ? 'rated'
              : full
              ? 'awaiting_feedback'
              : s?.status ?? row.state,
        ),
      );
      if (rated) results.putIfAbsent(row.slot, () => s);
      if (full && !rated) awaiting.add(s);
    }
    return CalibrationProgress(
      p,
      List.unmodifiable(attempts),
      Map.unmodifiable(results),
      List.unmodifiable(awaiting),
    );
  }

  /// Called at launch, before any new acquisition. Missing recordings from a
  /// terminated process leave their scheduled slot incomplete.
  Future<void> recoverInterruptedAttempts(String owner) async {
    final rows =
        await (db.select(db.calibrationAttempts)..where(
              (r) =>
                  r.ownerAccountId.equals(owner) & r.state.equals('reserved'),
            ))
            .get();
    for (final row in rows) {
      if (!await sessions.sessionExists(row.sessionId)) {
        await (db.update(db.calibrationAttempts)..where(
              (r) =>
                  r.sessionId.equals(row.sessionId) &
                  r.ownerAccountId.equals(owner),
            ))
            .write(
              const CalibrationAttemptsCompanion(state: Value('interrupted')),
            );
      }
    }
  }

  Future<void> interruptAttempt(String owner, String sessionId) async {
    final saved = await sessions.sessionExists(sessionId);
    if (saved) return;
    await (db.update(db.calibrationAttempts)..where(
          (r) => r.ownerAccountId.equals(owner) & r.sessionId.equals(sessionId),
        ))
        .write(const CalibrationAttemptsCompanion(state: Value('interrupted')));
  }

  /// A duplicate acquisition of the same reserved recording is idempotent.
  Future<int> reserveAttempt(String owner, String planId, String sessionId) =>
      db.transaction(() async {
        if (await (db.select(
              db.sessionTombstones,
            )..where((r) => r.sessionId.equals(sessionId))).getSingleOrNull() !=
            null) {
          throw StateError('Sessionen är raderad.');
        }
        final existing = await (db.select(
          db.calibrationAttempts,
        )..where((r) => r.sessionId.equals(sessionId))).getSingleOrNull();
        if (existing != null) {
          if (existing.ownerAccountId != owner || existing.planId != planId) {
            throw StateError('Sessionen tillhör en annan serie.');
          }
          if (existing.state != 'reserved' ||
              await sessions.sessionExists(sessionId)) {
            throw StateError('Försöket är redan avslutat.');
          }
          return existing.slot;
        }
        final deleted = await (db.select(
          db.uploadJobs,
        )..where((r) => r.sessionId.equals(sessionId))).getSingleOrNull();
        if (deleted != null) throw StateError('Sessions-ID används redan.');
        final state = await progress(owner, planId);
        final slot = state.nextSlot;
        if (slot == null) throw StateError('Serien är redan slutförd.');
        if (state.awaitingFeedback.isNotEmpty) {
          throw StateError('Slutför återkopplingen innan nästa session.');
        }
        if (state.attempts.any((a) => a.status == 'reserved')) {
          throw StateError('Ett försök är redan påbörjat.');
        }
        await db
            .into(db.calibrationAttempts)
            .insert(
              CalibrationAttemptsCompanion.insert(
                ownerAccountId: owner,
                sessionId: sessionId,
                planId: planId,
                slot: slot,
                createdAt: DateTime.now().toUtc(),
              ),
            );
        return slot;
      });

  Future<MeditationFeedback?> feedback(String owner, String sessionId) async {
    final row =
        await (db.select(db.meditationFeedbackRows)..where(
              (r) =>
                  r.ownerAccountId.equals(owner) &
                  r.sessionId.equals(sessionId),
            ))
            .getSingleOrNull();
    return row == null
        ? null
        : MeditationFeedback(
            ownerAccountId: owner,
            sessionId: sessionId,
            mentalBusyness: row.mentalBusyness,
            relaxation: row.relaxation,
            revision: row.revision,
          );
  }

  Future<List<SessionSummary>> pendingFeedback(String owner) async =>
      (await snapshot(owner)).pendingFeedback;

  Future<void> saveFeedback(
    String owner,
    String sessionId, {
    int? mentalBusyness,
    int? relaxation,
  }) => db.transaction(() async {
    if (await sessions.isTombstoned(owner, sessionId)) {
      throw StateError('Sessionen är raderad.');
    }
    if ([
      mentalBusyness,
      relaxation,
    ].any((v) => v != null && (v < 0 || v > 10))) {
      throw ArgumentError('Ratings must be integers from 0 to 10');
    }
    final saved = await sessions.summaryById(sessionId);
    if (saved == null || !_ownedCompleted(saved, owner)) {
      throw StateError(
        'Återkoppling kräver en egen session med tio slutförda minuter.',
      );
    }
    if (saved.manifest.meditation?['mode'] == 'calibration') {
      final attempt =
          await (db.select(db.calibrationAttempts)..where(
                (r) =>
                    r.ownerAccountId.equals(owner) &
                    r.sessionId.equals(sessionId),
              ))
              .getSingleOrNull();
      if (attempt == null ||
          !_completed(saved, await plan(owner, attempt.planId), attempt.slot)) {
        throw StateError('Sessionen matchar inte seriens låsta uppställning.');
      }
    }
    final old = await feedback(owner, sessionId);
    final busy = mentalBusyness ?? old?.mentalBusyness;
    final relaxed = relaxation ?? old?.relaxation;
    if (old != null &&
        old.mentalBusyness == busy &&
        old.relaxation == relaxed) {
      return;
    }
    await db
        .into(db.meditationFeedbackRows)
        .insertOnConflictUpdate(
          MeditationFeedbackRowsCompanion.insert(
            ownerAccountId: owner,
            sessionId: sessionId,
            mentalBusyness: Value(busy),
            relaxation: Value(relaxed),
            revision: (old?.revision ?? 0) + 1,
            syncState: const Value('pending'),
            attempts: const Value(0),
            lastError: const Value(null),
          ),
        );
    if (['fixed', 'calibration'].contains(saved.manifest.meditation?['mode'])) {
      await sessions.bumpEvidenceEpoch(owner);
    }
  });
}

class CalibrationState {
  const CalibrationState(this.progress, this.pendingFeedback);
  final List<CalibrationProgress> progress;
  final List<SessionSummary> pendingFeedback;
  Set<String> get revealedPlans => {
    for (final p in progress)
      if (p.complete) p.plan.id,
  };
}
