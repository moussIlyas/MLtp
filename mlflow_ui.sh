#!/usr/bin/env bash
set -a
[ -f .env ] && . ./.env
set +a

MLFLOW_TRACKING_URI="postgresql://${NEON_PGUSER}:${NEON_PGPASSWORD}@${NEON_PGHOST}:${NEON_PGPORT}/${NEON_PGDATABASE}?sslmode=${NEON_SSLMODE}"
export MLFLOW_TRACKING_URI

exec .venv/bin/mlflow ui --backend-store-uri "${MLFLOW_TRACKING_URI}" "$@"