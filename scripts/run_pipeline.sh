#!/usr/bin/env bash
# Generate data -> load into Postgres -> run tests -> build the dbt warehouse.
# Usage: ./scripts/run_pipeline.sh [extra args for the generator, e.g. --bookings 20000 --seed 7]
set -euo pipefail
cd "$(dirname "$0")/.."

PSQL=(docker compose exec -T db psql -U trainbooker -d trainbooker -v ON_ERROR_STOP=1)

echo "==> 1/5 starting database"
docker compose up -d --wait

echo "==> 2/5 generating data"
python3 generator/generate_data.py "$@"

echo "==> 3/5 loading CSVs"
"${PSQL[@]}" -f /sql/load/load_generated.sql

echo "==> 4/5 running OLTP tests"
"${PSQL[@]}" -q -f /sql/tests/test_constraints.sql
"${PSQL[@]}" -q -f /sql/tests/test_data_quality.sql

echo "==> 5/5 building the warehouse with dbt"
if command -v dbt >/dev/null 2>&1; then
    (cd dbt && dbt build --profiles-dir .)
else
    echo "    dbt not found - skipping. Install it with: pip install -r requirements.txt"
fi

echo "==> done. Explore the data with:"
echo "    docker compose exec -T db psql -U trainbooker -d trainbooker -f /sql/queries/data_profile.sql"
