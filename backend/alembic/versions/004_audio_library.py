"""Owned originals and recoverable canonical audio imports."""
from alembic import op
import sqlalchemy as sa

revision = '004_audio_library'
down_revision = '003_single_active_experiment'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table('audio_assets',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('user_id', sa.String(36), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('schema_version', sa.Integer(), nullable=False),
        sa.Column('filename', sa.String(255), nullable=False),
        sa.Column('source_format', sa.String(16), nullable=False),
        sa.Column('status', sa.String(16), nullable=False),
        sa.Column('original_bytes', sa.Integer(), nullable=False),
        sa.Column('original_sha256', sa.String(64), nullable=False),
        sa.Column('checksum_sha256', sa.String(64)),
        sa.Column('duration_seconds', sa.Float()),
        sa.Column('source_channels', sa.Integer()),
        sa.Column('error', sa.Text()),
        sa.Column('lease_token', sa.String(36)),
        sa.Column('lease_until', sa.DateTime(timezone=True)),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False))
    op.create_index('ix_audio_assets_user_id', 'audio_assets', ['user_id'])
    op.create_index('ix_audio_assets_status', 'audio_assets', ['status'])


def downgrade():
    op.drop_table('audio_assets')
