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
