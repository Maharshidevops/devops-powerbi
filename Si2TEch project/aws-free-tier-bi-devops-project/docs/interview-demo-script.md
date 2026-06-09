# Interview Demo Script

## 60-Second Pitch

I built a small RetailOps BI DevOps platform to match this role. It validates sales data with Python, loads it into PostgreSQL, uses SQL functions and triggers for summary and audit logic, exposes metrics through a Node.js API, includes an Airflow DAG for orchestration, and has a GitLab CI/CD pipeline for validation and deployment checks. For AWS, I designed it to run safely on a single EC2 instance with Docker Compose for a free-tier-friendly demo, while explaining how I would move it to RDS, ECR, EKS, and CloudWatch in production.

## Commands to Show

```bash
docker compose up -d postgres
python etl/validate_sales.py data/sample_sales.csv
python etl/load_sales.py data/sample_sales.csv
cd api && npm install && npm start
curl http://localhost:3000/health
curl http://localhost:3000/metrics/daily-sales
```

## Talking Points

- The ETL is idempotent because `sale_id` is the primary key and loads use `ON CONFLICT`.
- The database trigger writes audit records for inserted sales.
- The summary function refreshes BI-ready daily aggregates.
- GitLab CI catches Python validation, Node syntax issues, SQL file problems, and Docker Compose errors.
- EKS is relevant for the job, but not chosen for the free-tier demo because it is usually billable.

