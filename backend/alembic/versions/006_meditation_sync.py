"""Owned immutable calibration and mutable outcomes with separate training routing."""
from alembic import op
import sqlalchemy as sa

revision = '006_meditation_sync'
down_revision = '005_audio_profiles'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table('calibration_plans',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('user_id', sa.String(36), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('body_json', sa.Text(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False))
    op.create_index('ix_calibration_plans_user_id', 'calibration_plans', ['user_id'])
    op.create_table('meditation_feedback',
        sa.Column('user_id', sa.String(36), sa.ForeignKey('users.id'), primary_key=True),
        sa.Column('session_id', sa.String(64), primary_key=True),
        sa.Column('revision', sa.Integer(), nullable=False),
        sa.Column('body_json', sa.Text(), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False))
    op.create_table('meditation_training_jobs',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('user_id', sa.String(36), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('origin', sa.String(32), nullable=False),
        sa.Column('protocol_version', sa.String(64), nullable=False),
        sa.Column('dataset_fingerprint', sa.String(64), nullable=False),
        sa.Column('dataset_json', sa.Text(), nullable=False),
        sa.Column('status', sa.String(32), nullable=False),
        sa.Column('error', sa.Text()),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False),
        sa.UniqueConstraint('user_id', 'origin', 'protocol_version', 'dataset_fingerprint', name='uq_meditation_dataset'))
    op.create_index('ix_meditation_training_jobs_user_id', 'meditation_training_jobs', ['user_id'])
    op.create_table('meditation_training_requests',
        sa.Column('id', sa.String(36), primary_key=True),
        sa.Column('user_id', sa.String(36), sa.ForeignKey('users.id'), nullable=False),
        sa.Column('job_id', sa.String(36), sa.ForeignKey('meditation_training_jobs.id'), nullable=False),
        sa.Column('body_json', sa.Text(), nullable=False))
    op.create_index('ix_meditation_training_requests_user_id', 'meditation_training_requests', ['user_id'])


def downgrade():
    op.drop_table('meditation_training_requests')
    op.drop_table('meditation_training_jobs')
    op.drop_table('meditation_feedback')
    op.drop_table('calibration_plans')
