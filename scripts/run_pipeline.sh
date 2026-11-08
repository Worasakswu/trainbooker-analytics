#!/usr/bin/env bash
# Generate data -> load into Postgres -> run constraint + data-quality tests.
# Usage: ./scripts/run_pipeline.sh [extra args for the generator, e.g. --bookings 20000 --seed 7]
set -euo pipefail
cd "$(dirname "$0")/.."

PSQL=(docker compose exec -T db psql -U trainbooker -d trainbooker -v ON_ERROR_STOP=1)

echo "==> 1/4 starting database"
docker compose up -d --wait

echo "==> 2/4 generating data"
python3 generator/generate_data.py "$@"

echo "==> 3/4 loading CSVs"
"${PSQL[@]}" -f /sql/load/load_generated.sql

echo "==> 4/4 running tests"
"${PSQL[@]}" -q -f /sql/tests/test_constraints.sql
"${PSQL[@]}" -q -f /sql/tests/test_data_quality.sql

echo "==> done. Explore the data with:"
echo "    docker compose exec -T db psql -U trainbooker -d trainbooker -f /sql/queries/data_profile.sql"
