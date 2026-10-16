from collections.abc import Generator
import sqlite3

from sqlalchemy import create_engine, event
from sqlalchemy.engine import Engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker
from sqlalchemy.pool import StaticPool

from app.config import settings


class Base(DeclarativeBase):
    pass


@event.listens_for(Engine, 'connect')
def _sqlite_foreign_keys(connection, _record):
    if not isinstance(connection, sqlite3.Connection):
        return
    # SQLite otherwise accepts FK declarations without enforcing retention or
    # owner constraints. Set this outside a transaction on every connection.
    previous = connection.autocommit
    connection.autocommit = True
    try:
        cursor = connection.cursor()
        try:
            cursor.execute('PRAGMA foreign_keys=ON')
        finally:
            cursor.close()
    finally:
        connection.autocommit = previous


engine_kwargs: dict = {}
if settings.database_url.startswith("sqlite"):
    engine_kwargs["connect_args"] = {"check_same_thread": False}
    if settings.database_url in {"sqlite://", "sqlite:///:memory:"}:
        engine_kwargs["poolclass"] = StaticPool
engine = create_engine(settings.database_url, **engine_kwargs)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)


def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
