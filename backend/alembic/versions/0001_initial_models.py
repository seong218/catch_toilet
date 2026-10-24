"""initial restroom stall sensor and sensor event models

Revision ID: 0001
Revises:
Create Date: 2026-10-24 14:55:42.407713
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '0001'
down_revision: Union[str, Sequence[str], None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table('restrooms',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('name', sa.Text(), nullable=False),
    sa.Column('building', sa.Text(), nullable=False),
    sa.Column('floor', sa.Integer(), nullable=False),
    sa.Column('x', sa.Float(), nullable=False),
    sa.Column('y', sa.Float(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.CheckConstraint("building ~ '[^[:space:]]'", name='ck_restrooms_building_not_blank'),
    sa.CheckConstraint("name ~ '[^[:space:]]'", name='ck_restrooms_name_not_blank'),
    sa.CheckConstraint("x > '-Infinity'::float8 AND x < 'Infinity'::float8", name='ck_restrooms_x_finite'),
    sa.CheckConstraint("y > '-Infinity'::float8 AND y < 'Infinity'::float8", name='ck_restrooms_y_finite'),
    sa.CheckConstraint('id > 0', name='ck_restrooms_id_positive'),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_table('stalls',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('restroom_id', sa.Integer(), nullable=False),
    sa.Column('stall_number', sa.Integer(), nullable=False),
    sa.Column('occupied', sa.Boolean(), server_default=sa.text('false'), nullable=False),
    sa.Column('has_bidet', sa.Boolean(), server_default=sa.text('false'), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.CheckConstraint('id > 0', name='ck_stalls_id_positive'),
    sa.CheckConstraint('stall_number > 0', name='ck_stalls_number_positive'),
    sa.ForeignKeyConstraint(['restroom_id'], ['restrooms.id'], name='fk_stalls_restroom', ondelete='RESTRICT'),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('id', 'restroom_id', name='uq_stalls_id_restroom'),
    sa.UniqueConstraint('restroom_id', 'stall_number', name='uq_stalls_restroom_number')
    )
    op.create_table('sensors',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('device_id', sa.Text(), nullable=False),
    sa.Column('restroom_id', sa.Integer(), nullable=False),
    sa.Column('stall_id', sa.Integer(), nullable=False),
    sa.Column('sensor_type', sa.Text(), nullable=False),
    sa.Column('active', sa.Boolean(), server_default=sa.text('true'), nullable=False),
    sa.CheckConstraint("device_id ~ '[^[:space:]]'", name='ck_sensors_device_id_not_blank'),
    sa.CheckConstraint("sensor_type ~ '[^[:space:]]'", name='ck_sensors_type_not_blank'),
    sa.CheckConstraint('id > 0', name='ck_sensors_id_positive'),
    sa.ForeignKeyConstraint(['restroom_id'], ['restrooms.id'], name='fk_sensors_restroom', ondelete='RESTRICT'),
    sa.ForeignKeyConstraint(['stall_id', 'restroom_id'], ['stalls.id', 'stalls.restroom_id'], name='fk_sensors_stall_restroom', ondelete='RESTRICT'),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('device_id', name='uq_sensors_device_id')
    )
    op.create_index(op.f('ix_sensors_restroom_id'), 'sensors', ['restroom_id'], unique=False)
    op.create_index(op.f('ix_sensors_stall_id'), 'sensors', ['stall_id'], unique=False)
    op.create_table('sensor_events',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('sensor_id', sa.Integer(), nullable=False),
    sa.Column('event_type', sa.Text(), nullable=False),
    sa.Column('value', sa.Boolean(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.CheckConstraint("event_type ~ '[^[:space:]]'", name='ck_sensor_events_type_not_blank'),
    sa.CheckConstraint('id > 0', name='ck_sensor_events_id_positive'),
    sa.ForeignKeyConstraint(['sensor_id'], ['sensors.id'], name='fk_sensor_events_sensor', ondelete='RESTRICT'),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index('ix_sensor_events_sensor_id_created_at', 'sensor_events', ['sensor_id', 'created_at'], unique=False)


def downgrade() -> None:
    op.drop_index('ix_sensor_events_sensor_id_created_at', table_name='sensor_events')
    op.drop_table('sensor_events')
    op.drop_index(op.f('ix_sensors_stall_id'), table_name='sensors')
    op.drop_index(op.f('ix_sensors_restroom_id'), table_name='sensors')
    op.drop_table('sensors')
    op.drop_table('stalls')
    op.drop_table('restrooms')
