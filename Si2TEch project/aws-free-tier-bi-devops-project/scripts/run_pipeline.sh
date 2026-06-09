#!/usr/bin/env bash
set -euo pipefail

CSV_PATH="${1:-data/sample_sales.csv}"

source .venv/bin/activate
python etl/validate_sales.py "$CSV_PATH"
python etl/load_sales.py "$CSV_PATH"

echo "Pipeline completed for $CSV_PATH"

