"""Versioned, account/source-scoped validated meditation EEG artifacts."""
from alembic import op
import sqlalchemy as sa

revision = '008_personal_eeg_models'
down_revision = '007_meditation_deletions'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table('personal_eeg_models',
        sa.Column('id',sa.String(36),primary_key=True),
        sa.Column('user_id',sa.String(36),sa.ForeignKey('users.id'),nullable=False),
        sa.Column('job_id',sa.String(36),sa.ForeignKey('meditation_training_jobs.id',ondelete='SET NULL'),nullable=True,unique=True),
        sa.Column('origin',sa.String(32),nullable=False),
        sa.Column('protocol_version',sa.String(64),nullable=False),
        sa.Column('model_version',sa.String(64),nullable=False),
        sa.Column('body_json',sa.Text(),nullable=False),
        sa.Column('created_at',sa.DateTime(timezone=True),nullable=False))
    op.create_index('ix_personal_eeg_models_user_id','personal_eeg_models',['user_id'])


def downgrade():
    op.drop_table('personal_eeg_models')
