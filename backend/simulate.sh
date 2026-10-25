#!/bin/sh
set -eu
cd "$(dirname "$0")"
if [ ! -x .venv/bin/python ]; then
  echo 'backend/.venv가 필요합니다. backend/README.md의 로컬 Python 설치를 먼저 진행하세요.' >&2
  exit 1
fi
exec .venv/bin/python -m app.simulate "$@"
