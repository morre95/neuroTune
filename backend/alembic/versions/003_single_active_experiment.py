"""Allow at most one active experiment."""

from alembic import op

revision = "003_single_active_experiment"
down_revision = "002_session_deletions"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Earlier seeding could leave several active rows. Clear them; startup
    # seeding then reactivates the version in the contracts file.
    op.execute(
        "UPDATE experiments SET active = false "
        "WHERE (SELECT count(*) FROM experiments WHERE active) > 1"
    )
    op.execute("CREATE UNIQUE INDEX IF NOT EXISTS uq_experiments_one_active ON experiments (active) WHERE active")


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS uq_experiments_one_active")
