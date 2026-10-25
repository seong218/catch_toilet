"""Track fresh sensor reports and validity of historical bidet observations."""

from alembic import op
import sqlalchemy as sa

revision = "0006"
down_revision = "0005"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Do not infer liveness from an old state-change timestamp.
    op.add_column("sensors", sa.Column("last_seen_at", sa.DateTime(timezone=True), nullable=True))
    op.add_column("restroom_snapshots", sa.Column(
        "bidet_sample_valid", sa.Boolean(), nullable=False, server_default=sa.true(),
    ))


def downgrade() -> None:
    op.drop_column("restroom_snapshots", "bidet_sample_valid")
    op.drop_column("sensors", "last_seen_at")
