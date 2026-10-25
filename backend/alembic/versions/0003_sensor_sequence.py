"""Persist anti-replay sequence and index event retention scans."""

from alembic import op
import sqlalchemy as sa

revision = "0003"
down_revision = "0002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("sensors", sa.Column("last_sequence", sa.BigInteger(), nullable=False, server_default="0"))
    op.add_column("sensors", sa.Column("last_occupied", sa.Boolean(), nullable=False, server_default=sa.false()))
    op.create_check_constraint("ck_sensors_sequence_nonnegative", "sensors", "last_sequence >= 0")
    op.create_index("ix_sensor_events_created_at", "sensor_events", ["created_at"])


def downgrade() -> None:
    op.drop_index("ix_sensor_events_created_at", table_name="sensor_events")
    op.drop_constraint("ck_sensors_sequence_nonnegative", "sensors", type_="check")
    op.drop_column("sensors", "last_occupied")
    op.drop_column("sensors", "last_sequence")
