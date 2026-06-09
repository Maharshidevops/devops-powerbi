# Operations Runbook

## Pipeline Failure

1. Check GitLab job logs or Airflow task logs.
2. Confirm the source CSV exists and has the expected columns.
3. Run `python etl/validate_sales.py data/sample_sales.csv`.
4. Check PostgreSQL connectivity and credentials.
5. Re-run `python etl/load_sales.py data/sample_sales.csv`.
6. Check `etl_audit` for recent job status.

## Dashboard Is Empty

1. Query `raw_sales` row count.
2. Query `daily_sales_summary` row count.
3. Run `SELECT refresh_daily_sales_summary();`.
4. Check Superset database connection.
5. Clear dashboard cache or refresh chart data.

## API Is Down

1. Run `curl http://localhost:3000/health`.
2. Check Node.js process logs.
3. Confirm `.env` points to the correct database host.
4. Confirm PostgreSQL is healthy with `docker compose ps`.

## Database Is Slow

1. Identify slow SQL from API, Superset, or database logs.
2. Check indexes on date, product, and store columns.
3. Use `EXPLAIN ANALYZE` on slow queries.
4. Reduce dashboard default date ranges.
5. Add caching for repeated dashboard queries.

