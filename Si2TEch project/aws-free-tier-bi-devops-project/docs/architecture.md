# Architecture

```text
CSV / source system
        |
        v
Python validation script
        |
        v
Python loader script
        |
        v
PostgreSQL raw_sales table
        |
        +--> trigger writes etl_audit
        |
        +--> refresh_daily_sales_summary()
        |
        v
Summary tables and views
        |
        +--> Apache Superset dashboards
        |
        +--> Node.js metrics API
        |
        v
GitLab CI/CD validates code and promotes deployments
```

## Components

- **PostgreSQL:** Stores raw sales, audit records, data quality issues, summary tables, and BI views.
- **Python ETL:** Validates CSV data and loads it idempotently using `ON CONFLICT`.
- **Airflow DAG:** Schedules validation and loading as operational tasks.
- **Superset:** Connects to PostgreSQL for dashboards.
- **Node.js API:** Exposes health checks and selected metrics.
- **GitLab CI/CD:** Runs validation, syntax checks, Docker Compose checks, and manual deployment.

## Production Improvements

- Replace local Postgres with RDS PostgreSQL when budget allows.
- Store secrets in AWS SSM Parameter Store or Secrets Manager.
- Add CloudWatch agent or Prometheus/Grafana for deeper observability.
- Use ECR for container images.
- Use EKS only when the budget supports Kubernetes control plane costs.

