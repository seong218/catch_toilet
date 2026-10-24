#!/bin/sh
set -eu

# Compose waits for PostgreSQL health before starting this development container.
# A failed migration must stop startup; seed data remains an explicit command.
alembic upgrade head

# One process owns the in-memory WebSocket manager. exec forwards stop signals.
exec uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 1
