"""Owned monotonic deletion epochs for conditional evidence publication."""
import json
from collections import defaultdict

from alembic import op
import sqlalchemy as sa

revision = '007_meditation_deletions'
down_revision = '006_meditation_sync'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table('owner_deletion_epochs',
        sa.Column('user_id', sa.String(36), sa.ForeignKey('users.id'), primary_key=True),
        sa.Column('epoch', sa.Integer(), nullable=False))

    # Older deletion acknowledged raw removal but left independent ratings/jobs.
    # Scrub that already-deleted evidence during upgrade, before new workers use it.
    bind = op.get_bind()
    meta = sa.MetaData()
    markers = sa.Table('session_deletions', meta, autoload_with=bind)
    feedback = sa.Table('meditation_feedback', meta, autoload_with=bind)
    jobs = sa.Table('meditation_training_jobs', meta, autoload_with=bind)
    requests = sa.Table('meditation_training_requests', meta, autoload_with=bind)
    epochs = sa.Table('owner_deletion_epochs', meta, autoload_with=bind)
    owners = defaultdict(set)
    for row in bind.execute(sa.select(markers.c.user_id, markers.c.session_id)):
        owners[row.user_id].add(row.session_id)
    for owner, ids in owners.items():
        bind.execute(epochs.insert().values(user_id=owner, epoch=1))
        bind.execute(feedback.delete().where(feedback.c.user_id == owner, feedback.c.session_id.in_(ids)))
        affected = set()
        for row in bind.execute(sa.select(jobs).where(jobs.c.user_id == owner)):
            try:
                dataset = json.loads(row.dataset_json)
                if not isinstance(dataset, list):
                    raise ValueError('Unsupported snapshot')
                if any(isinstance(item, dict) and item.get('session_id') in ids for item in dataset):
                    affected.add(row.id)
            except (ValueError, TypeError):
                affected.add(row.id)
        for row in bind.execute(sa.select(requests).where(requests.c.user_id == owner)):
            try:
                if json.loads(row.body_json).get('session_id') in ids:
                    affected.add(row.job_id)
            except (ValueError, TypeError, AttributeError):
                affected.add(row.job_id)
        if affected:
            bind.execute(requests.delete().where(requests.c.user_id == owner, requests.c.job_id.in_(affected)))
            bind.execute(jobs.delete().where(jobs.c.user_id == owner, jobs.c.id.in_(affected)))


def downgrade():
    op.drop_table('owner_deletion_epochs')
