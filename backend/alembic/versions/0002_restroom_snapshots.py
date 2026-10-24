"""Add historical restroom availability observations.

Revision ID: 0002
Revises: 0001
"""

from alembic import op
import sqlalchemy as sa

revision = "0002"
down_revision = "0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "restroom_snapshots",
        sa.Column("id", sa.Integer(), nullable=False),
        sa.Column("restroom_id", sa.Integer(), nullable=False),
        sa.Column("total_stalls", sa.Integer(), nullable=False),
        sa.Column("available_stalls", sa.Integer(), nullable=False),
        sa.Column("available_bidet_stalls", sa.Integer(), nullable=False),
        sa.Column("captured_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("is_test_data", sa.Boolean(), nullable=False),
        sa.CheckConstraint("id > 0", name="ck_restroom_snapshots_id_positive"),
        sa.CheckConstraint("total_stalls >= 0", name="ck_restroom_snapshots_total_nonnegative"),
        sa.CheckConstraint(
            "available_stalls >= 0 AND available_stalls <= total_stalls",
            name="ck_restroom_snapshots_available_range",
        ),
        sa.CheckConstraint(
            "available_bidet_stalls >= 0 AND available_bidet_stalls <= available_stalls",
            name="ck_restroom_snapshots_bidet_range",
        ),
        sa.CheckConstraint("isfinite(captured_at)", name="ck_restroom_snapshots_captured_finite"),
        sa.ForeignKeyConstraint(
            ["restroom_id"], ["restrooms.id"], name="fk_restroom_snapshots_restroom", ondelete="RESTRICT",
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("restroom_id", "captured_at", name="uq_restroom_snapshots_room_captured_at"),
    )


def downgrade() -> None:
    op.drop_table("restroom_snapshots")
