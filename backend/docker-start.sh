#!/bin/sh
set -eu

# One process owns the in-memory WebSocket manager. exec forwards stop signals.
# The separate migration job owns admin credentials. This process has only DML.
exec uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 1 --no-proxy-headers --no-access-log --ws-max-size 4096 --ws-max-queue 4
