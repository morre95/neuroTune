import 'dart:convert';
import 'package:drift/drift.dart';
import 'database.dart';

/// Runs inside the caller's evidence-retirement transaction. Never uses a
/// generic epoch to revoke unrelated models or the explicit fixed preference.
Future<void> retireMeditationLearning(
  AppDatabase db,
  String owner,
  Set<String> deleted,
) async {
  final rows =
      await (db.select(db.kvStore)..where(
            (r) =>
                r.key.like('meditation_model:v1:$owner:%') |
                r.key.like('meditation_action_stats:v1:$owner:%'),
          ))
          .get();
  bool intersects(Iterable<dynamic> ids) => ids.any(deleted.contains);
  for (final row in rows) {
    if (!row.key.startsWith('meditation_model:v1:$owner:') &&
        !row.key.startsWith('meditation_action_stats:v1:$owner:')) {
      continue;
    }
    try {
      final body = jsonDecode(row.value) as Map<String, dynamic>;
      if (row.key.startsWith('meditation_model:')) {
        if (body['missing'] == true || body['invalid'] == true) continue;
        final ids = body['included_session_ids'] as List;
        if (!intersects(ids)) continue;
        // Keep a truthful fallback marker, without deleted provenance,
        // coefficients or fixed-minute initialization summaries.
        await db.putKv(
          row.key,
          jsonEncode({
            for (final field in [
              'schema_version',
              'preprocessing_version',
              'quality_version',
              'protocol_version',
              'id',
              'owner_account_id',
              'origin',
              'model_version',
              'dataset_fingerprint',
              'server_deletion_epoch',
              'created_at',
            ])
              field: body[field],
            'status': 'revoked',
            'reasons': [
              'Learning evidence was deleted; use preferred fixed playback',
            ],
            'included_session_ids': [],
            'evidence': [],
            'fixed_minutes': [],
            'validation': {
              'session_count': 0,
              'mae': null,
              'correlation': null,
              'context_mae': null,
              'gates': <String, bool>{},
            },
          }),
        );
      } else {
        final evidence = body['model_evidence'] as List;
        if (intersects(evidence.map((e) => (e as Map)['session_id']))) {
          await db.deleteKv(row.key);
          continue;
        }
        final contributions = body['contributions'] as List;
        final retained = contributions
            .where((c) => !deleted.contains((c as Map)['session_id']))
            .toList();
        if (retained.length != contributions.length) {
          await db.putKv(
            row.key,
            jsonEncode({...body, 'contributions': retained}),
          );
        }
      }
    } on FormatException {
      await db.deleteKv(row.key);
    } on TypeError {
      // Unreadable owned provenance cannot be proven unaffected.
      await db.deleteKv(row.key);
    }
  }
}

/// A new/failed latest result cannot silently reuse old-version proxy totals.
Future<void> retireSupersededMeditationStatistics(
  AppDatabase db,
  String owner,
  String origin,
  String? readyVersion,
) async {
  final rows =
      await (db.select(db.kvStore)..where(
            (r) => r.key.like(
              'meditation_action_stats:v1:$owner:$origin:meditation-1:%',
            ),
          ))
          .get();
  for (final row in rows) {
    if (!row.key.startsWith(
      'meditation_action_stats:v1:$owner:$origin:meditation-1:',
    )) {
      continue;
    }
    bool retain = false;
    try {
      final body = jsonDecode(row.value) as Map;
      retain =
          readyVersion != null &&
          body['owner_account_id'] == owner &&
          body['origin'] == origin &&
          body['protocol_version'] == 'meditation-1' &&
          body['model_version'] == readyVersion;
    } on FormatException {
      // Retire unprovable scope.
    } on TypeError {
      // Retire unprovable scope.
    }
    if (!retain) await db.deleteKv(row.key);
  }
}
