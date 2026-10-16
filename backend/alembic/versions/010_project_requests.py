"""Durable owner/operation-scoped project request receipts."""
from alembic import op
import sqlalchemy as sa

revision = '010_project_requests'
down_revision = '009_audio_projects'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table('audio_project_requests',
        sa.Column('user_id', sa.String(36), sa.ForeignKey('users.id'), primary_key=True),
        sa.Column('operation', sa.String(24), primary_key=True),
        sa.Column('request_id', sa.String(36), primary_key=True),
        # No project FK: deletion must not make old retries create it again.
        sa.Column('project_id', sa.String(36), nullable=False),
        sa.Column('payload_sha256', sa.String(64), nullable=False),
        sa.Column('response_json', sa.Text(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False))


def downgrade():
    op.drop_table('audio_project_requests')
