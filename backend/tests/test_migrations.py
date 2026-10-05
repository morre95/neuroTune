from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, inspect

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
