"""Campus inventory, geographic coordinates, and unobserved stall states."""
from alembic import op
import sqlalchemy as sa

revision = "0004"
down_revision = "0003"
branch_labels = None
depends_on = None


def upgrade():
    for column in (
        sa.Column("latitude", sa.Float()), sa.Column("longitude", sa.Float()),
        sa.Column("gender", sa.Text(), nullable=False, server_default="unisex"),
        sa.Column("location_source", sa.Text(), nullable=False, server_default="unverified"),
        sa.Column("bidet_stalls", sa.Integer()),
        sa.Column("accessible_stalls", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("data_key", sa.Text()),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
    ):
        op.add_column("restrooms", column)
    op.create_unique_constraint("uq_restrooms_data_key", "restrooms", ["data_key"])
    for name, expression in (
        ("gps_pair", "(latitude IS NULL) = (longitude IS NULL)"),
        ("latitude_range", "latitude BETWEEN -90 AND 90"),
        ("longitude_range", "longitude BETWEEN -180 AND 180"),
        ("gender", "gender IN ('male', 'female', 'unisex')"),
        ("bidet_count", "bidet_stalls >= 0"), ("accessible_count", "accessible_stalls >= 0"),
    ):
        op.create_check_constraint("ck_restrooms_" + name, "restrooms", expression)
    op.alter_column("stalls", "occupied", nullable=True)
    op.alter_column("stalls", "has_bidet", nullable=True)
    op.add_column("stalls", sa.Column("is_accessible", sa.Boolean()))


def downgrade():
    # An unknown observation cannot be truthfully converted to false/true.
    connection = op.get_bind()
    if connection.scalar(sa.text("SELECT EXISTS(SELECT 1 FROM stalls WHERE occupied IS NULL OR has_bidet IS NULL)")):
        raise RuntimeError("Cannot downgrade while unknown stall states/facilities exist")
    op.drop_column("stalls", "is_accessible")
    op.alter_column("stalls", "occupied", nullable=False)
    op.alter_column("stalls", "has_bidet", nullable=False)
    for name in ("gps_pair", "latitude_range", "longitude_range", "gender", "bidet_count", "accessible_count"):
        op.drop_constraint("ck_restrooms_" + name, "restrooms", type_="check")
    op.drop_constraint("uq_restrooms_data_key", "restrooms", type_="unique")
    for name in ("latitude", "longitude", "gender", "location_source", "bidet_stalls", "accessible_stalls", "data_key", "is_active"):
        op.drop_column("restrooms", name)
