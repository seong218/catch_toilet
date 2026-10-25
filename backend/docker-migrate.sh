#!/bin/sh
set -eu

alembic upgrade head
python -m app.provision_runtime_role
