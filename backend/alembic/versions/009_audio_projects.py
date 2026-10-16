"""Owned projects, saved revisions and retention of referenced audio."""
from alembic import op
import sqlalchemy as sa

revision = '009_audio_projects'
down_revision = '008_personal_eeg_models'
branch_labels = None
depends_on = None


def upgrade():
    # Additive unique indexes enable owner-paired FKs without rewriting legacy
    # assets/profile metadata, published checksums, or their existing keys.
    op.create_index('uq_audio_assets_id_user', 'audio_assets', ['id', 'user_id'], unique=True)
    op.create_index('uq_audio_profile_versions_id_user', 'audio_profile_versions',
                    ['id', 'user_id'], unique=True)
    op.create_table('audio_projects',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('user_id', sa.String(36), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('schema_version', sa.Integer(), nullable=False),
        sa.Column('revision', sa.BigInteger(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint('id', 'user_id', name='uq_audio_projects_id_user'),
        sa.CheckConstraint('schema_version = 1', name='ck_audio_projects_schema'),
        sa.CheckConstraint('revision BETWEEN 1 AND 9007199254740991', name='ck_audio_projects_revision'))
    op.create_index('ix_audio_projects_owner_updated', 'audio_projects', ['user_id', 'updated_at', 'id'])
    op.create_table('audio_project_revisions',
        sa.Column('project_id', sa.String(36), primary_key=True),
        sa.Column('revision', sa.BigInteger(), primary_key=True),
        sa.Column('user_id', sa.String(36), nullable=False),
        sa.Column('name', sa.String(120), nullable=False),
        sa.Column('recipe_json', sa.Text(), nullable=False),
        sa.Column('settings_json', sa.Text(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint('project_id', 'revision', 'user_id', name='uq_audio_project_revisions_owner'),
        sa.ForeignKeyConstraint(['project_id', 'user_id'], ['audio_projects.id', 'audio_projects.user_id'],
            ondelete='CASCADE', name='fk_audio_project_revisions_owner'),
        sa.CheckConstraint('revision BETWEEN 1 AND 9007199254740991', name='ck_audio_project_revisions_number'),
        sa.CheckConstraint('length(trim(name)) > 0 AND length(name) <= 120', name='ck_audio_project_revisions_name'))
    op.create_table('audio_project_sources',
        sa.Column('project_id', sa.String(36), primary_key=True),
        sa.Column('revision', sa.BigInteger(), primary_key=True),
        sa.Column('source_id', sa.String(36), primary_key=True),
        sa.Column('user_id', sa.String(36), nullable=False),
        sa.Column('asset_id', sa.String(36), nullable=False),
        sa.Column('kind', sa.String(24), nullable=False),
        sa.Column('profile_version_id', sa.String(36)),
        sa.ForeignKeyConstraint(['project_id', 'revision', 'user_id'],
            ['audio_project_revisions.project_id', 'audio_project_revisions.revision',
             'audio_project_revisions.user_id'], ondelete='CASCADE', name='fk_audio_project_sources_revision'),
        sa.ForeignKeyConstraint(['asset_id', 'user_id'], ['audio_assets.id', 'audio_assets.user_id'],
            ondelete='RESTRICT', name='fk_audio_project_sources_asset'),
        sa.ForeignKeyConstraint(['profile_version_id', 'user_id'],
            ['audio_profile_versions.id', 'audio_profile_versions.user_id'],
            ondelete='RESTRICT', name='fk_audio_project_sources_profile'),
        sa.CheckConstraint("(kind = 'asset' AND profile_version_id IS NULL) OR "
            "(kind = 'profile_background' AND profile_version_id IS NOT NULL)", name='ck_audio_project_sources_kind'))
    op.create_index('ix_audio_project_sources_asset_owner', 'audio_project_sources', ['asset_id', 'user_id'])
    op.create_index('ix_audio_project_sources_profile_owner', 'audio_project_sources', ['profile_version_id', 'user_id'])


def downgrade():
    op.drop_table('audio_project_sources')
    op.drop_table('audio_project_revisions')
    op.drop_table('audio_projects')
    op.drop_index('uq_audio_profile_versions_id_user', table_name='audio_profile_versions')
    op.drop_index('uq_audio_assets_id_user', table_name='audio_assets')
