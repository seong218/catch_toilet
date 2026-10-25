"""Require an explicit start before collecting usage statistics."""

from alembic import op
import sqlalchemy as sa

revision = "0007"
down_revision = "0006"
branch_labels = None
depends_on = None


def upgrade() -> None:
    table = op.create_table(
        "statistics_tracking",
        sa.Column("id", sa.Integer(), primary_key=True, autoincrement=False),
        sa.Column("enabled", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("stopped_at", sa.DateTime(timezone=True), nullable=True),
        sa.CheckConstraint("id = 1", name="ck_statistics_tracking_singleton"),
        sa.CheckConstraint(
            "NOT enabled OR (started_at IS NOT NULL AND stopped_at IS NULL)",
            name="ck_statistics_tracking_started",
        ),
        sa.CheckConstraint(
            "stopped_at IS NULL OR (started_at IS NOT NULL AND stopped_at >= started_at)",
            name="ck_statistics_tracking_order",
        ),
        sa.CheckConstraint(
            "isfinite(started_at) AND isfinite(stopped_at)",
            name="ck_statistics_tracking_finite",
        ),
    )
    op.bulk_insert(table, [{"id": 1, "enabled": False}])


def downgrade() -> None:
    op.drop_table("statistics_tracking")
