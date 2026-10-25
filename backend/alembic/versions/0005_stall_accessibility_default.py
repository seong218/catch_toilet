"""Default stall accessibility to false, including existing unknown values."""

from alembic import op
import sqlalchemy as sa

revision = "0005"
down_revision = "0004"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.alter_column(
        "stalls", "is_accessible", existing_type=sa.Boolean(),
        server_default=sa.false(),
    )
    # Preserve known true/false values and every other stall field.
    op.execute("UPDATE stalls SET is_accessible = false WHERE is_accessible IS NULL")
    op.alter_column(
        "stalls", "is_accessible", existing_type=sa.Boolean(), nullable=False,
    )


def downgrade() -> None:
    # The old unknown values cannot be reconstructed; keep the stored booleans.
    op.alter_column(
        "stalls", "is_accessible", existing_type=sa.Boolean(),
        nullable=True, server_default=None,
    )
