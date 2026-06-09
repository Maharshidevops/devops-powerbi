#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f ".env" ]]; then
  cp .env.example .env
fi

docker compose up -d postgres
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python etl/validate_sales.py data/sample_sales.csv
python etl/load_sales.py data/sample_sales.csv

echo "Bootstrap complete. Start the API with: cd api && npm install && npm start"

