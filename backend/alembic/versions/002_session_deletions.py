"""Remember session deletions without retaining signal data."""

from alembic import op
import sqlalchemy as sa

revision = "002_session_deletions"
down_revision = "001_initial"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "session_deletions",
        sa.Column("user_id", sa.String(36), sa.ForeignKey("users.id"), primary_key=True),
        sa.Column("session_id", sa.String(64), primary_key=True),
        sa.Column("raw_path", sa.Text(), nullable=True),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=False),
    )


def downgrade() -> None:
    op.drop_table("session_deletions")
