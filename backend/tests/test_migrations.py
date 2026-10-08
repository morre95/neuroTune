import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.exc import IntegrityError

from app.config import settings


def test_session_deletion_migration_preserves_existing_schema(tmp_path, monkeypatch):
    url = f"sqlite:///{tmp_path / 'migration.db'}"
    monkeypatch.setattr(settings, "database_url", url)
    config = Config("alembic.ini")
    command.upgrade(config, "001_initial")
    db = create_engine(url)
    assert "session_deletions" not in inspect(db).get_table_names()
    command.upgrade(config, "head")
    schema = inspect(db)
    assert "sessions" in schema.get_table_names()
    assert "session_deletions" in schema.get_table_names()
    assert schema.get_pk_constraint("session_deletions")["constrained_columns"] == ["user_id", "session_id"]
    db.dispose()


def test_single_active_migration_clears_duplicate_active_experiments(tmp_path, monkeypatch):
    url = f"sqlite:///{tmp_path / 'migration.db'}"
    monkeypatch.setattr(settings, "database_url", url)
    config = Config("alembic.ini")
    command.upgrade(config, "002_session_deletions")
    db = create_engine(url)
    with db.begin() as connection:
        connection.execute(
            text("INSERT INTO experiments (id, version, body, active) VALUES ('a', '1', '{}', true), ('b', '2', '{}', true)")
        )
    command.upgrade(config, "head")
    with db.connect() as connection:
        active = connection.execute(text("SELECT count(*) FROM experiments WHERE active")).scalar_one()
        assert active == 0
        with pytest.raises(IntegrityError):
            connection.execute(text("UPDATE experiments SET active = true"))
    command.downgrade(config, "002_session_deletions")
    db.dispose()


def test_meditation_sync_migration_preserves_legacy_and_durable_revision_queues(tmp_path, monkeypatch):
    url = f"sqlite:///{tmp_path / 'meditation-migration.db'}"
    monkeypatch.setattr(settings, 'database_url', url)
    config = Config('alembic.ini')
    command.upgrade(config, '005_audio_profiles')
    db = create_engine(url)
    with db.begin() as connection:
        connection.execute(text("INSERT INTO users (id,email,password_hash,created_at) VALUES ('legacy','legacy@test','hash','2026-01-01')"))
        connection.execute(text("INSERT INTO sessions (id,user_id,checksum,origin,experiment_version,manifest_json,decisions_json,frames_json,raw_path,created_at) VALUES ('old','legacy','checksum','muse','old-version','{}','[]','[]','original.bin','2026-01-01')"))
    command.upgrade(config, 'head')
    schema = inspect(db)
    assert {'calibration_plans', 'meditation_feedback', 'meditation_training_jobs', 'meditation_training_requests'}.issubset(schema.get_table_names())
    with db.connect() as connection:
        assert connection.execute(text("SELECT raw_path FROM sessions WHERE id='old'")).scalar_one() == 'original.bin'
    command.downgrade(config, '005_audio_profiles')
    assert 'meditation_feedback' not in inspect(db).get_table_names()
    db.dispose()


def test_meditation_deletion_migration_scrubs_preexisting_deleted_evidence_and_keeps_retained_data(tmp_path, monkeypatch):
    url = f"sqlite:///{tmp_path / 'deletion-migration.db'}"
    monkeypatch.setattr(settings, 'database_url', url)
    config = Config('alembic.ini')
    command.upgrade(config, '006_meditation_sync')
    db = create_engine(url)
    with db.begin() as connection:
        connection.execute(text("INSERT INTO users VALUES ('owner','owner@test','hash','2026-01-01')"))
        connection.execute(text("INSERT INTO session_deletions VALUES ('owner','deleted',NULL,'2026-01-01')"))
        connection.execute(text("INSERT INTO meditation_feedback VALUES ('owner','deleted',1,'{}','2026-01-01')"))
        connection.execute(text("INSERT INTO meditation_training_jobs VALUES ('old-job','owner','muse','meditation-1','old','[{\"session_id\":\"deleted\"}]','queued',NULL,'2026-01-01'), ('kept-job','owner','simulator','meditation-1','kept','[{\"session_id\":\"kept\"}]','queued',NULL,'2026-01-01')"))
        connection.execute(text("INSERT INTO meditation_training_requests VALUES ('old-request','owner','old-job','{\"session_id\":\"deleted\"}')"))
    command.upgrade(config, 'head')
    with db.connect() as connection:
        assert connection.execute(text('SELECT count(*) FROM meditation_feedback')).scalar_one() == 0
        assert connection.execute(text('SELECT id FROM meditation_training_jobs')).scalars().all() == ['kept-job']
        assert connection.execute(text('SELECT count(*) FROM meditation_training_requests')).scalar_one() == 0
        assert connection.execute(text('SELECT epoch FROM owner_deletion_epochs')).scalar_one() == 1
        assert connection.execute(text('SELECT count(*) FROM session_deletions')).scalar_one() == 1
    command.downgrade(config, '006_meditation_sync')
    assert 'owner_deletion_epochs' not in inspect(db).get_table_names()
    db.dispose()


def test_personal_model_migration_follows_reviewed_deletion_epoch_and_preserves_jobs(tmp_path,monkeypatch):
    url=f"sqlite:///{tmp_path/'model.db'}"
    monkeypatch.setattr(settings,'database_url',url)
    config=Config('alembic.ini')
    command.upgrade(config,'007_meditation_deletions')
    db=create_engine(url)
    command.upgrade(config,'head')
    schema=inspect(db)
    assert 'personal_eeg_models' in schema.get_table_names()
    fk=[fk for fk in schema.get_foreign_keys('personal_eeg_models') if fk['referred_table']=='meditation_training_jobs'][0]
    assert fk['options']['ondelete']=='SET NULL'
    command.downgrade(config,'007_meditation_deletions')
    assert 'personal_eeg_models' not in inspect(db).get_table_names()
    assert 'meditation_training_jobs' in inspect(db).get_table_names()
    db.dispose()
