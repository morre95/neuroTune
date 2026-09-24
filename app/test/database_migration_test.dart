import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neurotune/data/database.dart';
import 'package:neurotune/data/repository.dart';

void main() {
  test('new upload jobs retain their account owner', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = SessionRepository(database);

    await repository.enqueueUpload(
      'session-1',
      'checksum',
      '/tmp/session.bin',
      'Person@Example.com',
    );

    expect(
      (await repository.pendingUploads()).single.ownerEmail,
      'person@example.com',
    );
  });

  test('version 1 upload jobs survive the owner migration', () async {
    final database = AppDatabase(
      NativeDatabase.memory(
        setup: (sqlite) {
          sqlite.execute('''
            CREATE TABLE upload_jobs (
              session_id TEXT NOT NULL PRIMARY KEY,
              checksum TEXT NOT NULL,
              payload_path TEXT NOT NULL,
              state TEXT NOT NULL,
              attempts INTEGER NOT NULL DEFAULT 0,
              last_error TEXT
            )
          ''');
          sqlite.execute('''
            INSERT INTO upload_jobs
            (session_id, checksum, payload_path, state)
            VALUES ('legacy', 'checksum', '/tmp/legacy.bin', 'pending')
          ''');
          sqlite.execute('PRAGMA user_version = 1');
        },
      ),
    );
    addTearDown(database.close);
    final repository = SessionRepository(database);

    await repository.claimLegacyUploads('Person@Example.com');
    final jobs = await repository.pendingUploads();

    expect(jobs, hasLength(1));
    expect(jobs.single.sessionId, 'legacy');
    expect(jobs.single.ownerEmail, 'person@example.com');
  });
}
