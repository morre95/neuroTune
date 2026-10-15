"""Durable renders and immutable personal profile versions."""
from alembic import op
import sqlalchemy as sa

revision = '005_audio_profiles'
down_revision = '004_audio_library'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table('audio_renders',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('user_id', sa.String(36), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('recipe_json', sa.Text(), nullable=False),
        sa.Column('status', sa.String(16), nullable=False),
        sa.Column('progress', sa.Float(), nullable=False),
        sa.Column('normalization_factor', sa.Float()),
        sa.Column('checksum_sha256', sa.String(64)),
        sa.Column('preview_checksum_sha256', sa.String(64)),
        sa.Column('error', sa.Text()),
        sa.Column('lease_token', sa.String(36)),
        sa.Column('lease_until', sa.DateTime(timezone=True)),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False))
    op.create_index('ix_audio_renders_user_id', 'audio_renders', ['user_id'])
    op.create_index('ix_audio_renders_status', 'audio_renders', ['status'])
    op.create_table('audio_profile_versions',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('profile_id', sa.String(36), nullable=False),
        sa.Column('user_id', sa.String(36), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('version', sa.Integer(), nullable=False),
        sa.Column('render_id', sa.String(36), sa.ForeignKey('audio_renders.id'), nullable=False),
        sa.Column('body_json', sa.Text(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint('profile_id', 'version', name='uq_audio_profile_version'))
    op.create_index('ix_audio_profile_versions_user_id', 'audio_profile_versions', ['user_id'])
    op.create_index('ix_audio_profile_versions_profile_id', 'audio_profile_versions', ['profile_id'])


def downgrade():
    op.drop_table('audio_profile_versions')
    op.drop_table('audio_renders')
