"""Durable idempotency receipts: migration, isolation and transaction boundaries."""
from datetime import UTC, datetime

import pytest
from sqlalchemy import create_engine, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.models import AudioProjectRequest
from test_projects import seed, storage


def receipt(owner, **changes):
    values = dict(user_id=owner, operation='create', request_id='request-1',
        project_id='project-1', payload_sha256='a' * 64,
        response_json='{"revision":1}', created_at=datetime.now(UTC))
    values.update(changes)
    return AudioProjectRequest(**values)


def test_receipt_is_durable_and_key_is_owner_operation_request(storage):
    project, other = seed(storage)
    owner = project['owner_account_id']
    with Session(storage) as db:
        db.add_all([receipt(owner), receipt(other), receipt(owner, operation='save')])
        db.commit()
        db.add(receipt(owner, project_id='different-resource'))
        with pytest.raises(IntegrityError):
            db.commit()
        db.rollback()
    storage.dispose()
    reopened = create_engine(storage.url)
    try:
        with Session(reopened) as db:
            saved = db.get(AudioProjectRequest, (owner, 'create', 'request-1'))
            assert saved.response_json == '{"revision":1}'
            assert saved.project_id == 'project-1'
            assert saved.payload_sha256 == 'a' * 64
            assert db.query(AudioProjectRequest).count() == 3
    finally:
        reopened.dispose()


def test_receipt_rolls_back_with_failed_work(storage):
    project, _ = seed(storage)
    with Session(storage) as db:
        db.add(receipt(project['owner_account_id']))
        db.flush()
        db.rollback()
        assert db.query(AudioProjectRequest).count() == 0
        # No project FK: a future deletion must retain the receipt/tombstone.
        db.add(receipt('missing-owner'))
        with pytest.raises(IntegrityError):
            db.commit()
        db.rollback()
        assert db.execute(text('SELECT count(*) FROM audio_projects')).scalar_one() == 0
