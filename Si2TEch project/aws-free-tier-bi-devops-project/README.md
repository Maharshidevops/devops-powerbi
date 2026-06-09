# AWS Free-Tier-Friendly BI DevOps Project

This portfolio project demonstrates the core skills from the SI2 Tech job description using a practical mini analytics platform:

- Apache Superset-style BI dashboard layer
- Apache Airflow-style workflow orchestration
- PostgreSQL relational database with SQL procedures and triggers
- Python ETL and data validation
- Node.js API service
- Shell automation
- GitLab CI/CD pipeline design
- AWS deployment notes that avoid non-free-tier surprises

## Project Idea

**RetailOps Analytics Platform**: a small real-life analytics system for tracking daily sales, refunds, product performance, and data quality. It is useful for a small shop, e-commerce side project, or internal operations team.

The pipeline loads CSV sales data into PostgreSQL, validates it, creates analytics tables, exposes a Node.js health/API endpoint, and can be visualized in Superset.

## Why This Fits the Job Description

| Requirement | Where It Appears |
|---|---|
| Apache Superset | `docker-compose.yml`, dashboard notes |
| Apache Airflow | `airflow/dags/retailops_daily_pipeline.py` |
| RDBMS | PostgreSQL schema in `sql/` |
| SQL / PL/SQL | Stored procedure-style functions and triggers in `sql/02_procedures.sql` |
| Python scripting | `etl/load_sales.py`, `etl/validate_sales.py` |
| Node.js | `api/server.js` |
| Shell scripting | `scripts/bootstrap.sh`, `scripts/run_pipeline.sh` |
| GitLab CI/CD | `.gitlab-ci.yml` |
| Docker / containers | `docker-compose.yml` |
| AWS exposure | `docs/aws-free-tier-deploy.md` |
| Monitoring mindset | `docs/runbook.md` |

## Important AWS Free Tier Note

AWS Free Tier changed for accounts created on or after **July 15, 2025**. AWS now distinguishes older 12-month free tier behavior from newer Free Plan / credit-based behavior. Check your account’s Billing console before deploying anything.

For interview safety:

- Use one small EC2 instance or run locally.
- Avoid EKS for a free-tier demo because EKS control plane usage is normally billable.
- Avoid NAT Gateway for demos because it can create charges.
- Create AWS Budgets and billing alerts before deploying.
- Destroy resources after practice.

Official references:

- AWS Free Tier overview: https://docs.aws.amazon.com/awsaccountbilling/latest/aboutv2/free-tier.html
- EC2 Free Tier tracking: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-free-tier-usage.html
- RDS Free Tier FAQ: https://aws.amazon.com/rds/faqs/

## Local Quick Start

Prerequisites:

- Docker Desktop or Docker Engine
- Docker Compose
- Python 3.11+
- Node.js 20+

Run:

```bash
cp .env.example .env
docker compose up -d postgres
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python etl/validate_sales.py data/sample_sales.csv
python etl/load_sales.py data/sample_sales.csv
cd api
npm install
npm start
```

Optional BI stack:

```bash
docker compose --profile bi up -d
```

Optional Airflow stack:

```bash
docker compose --profile airflow up -d
```

Airflow demo login:

- URL: `http://localhost:8080`
- Username: `admin`
- Password: `admin`

Change these credentials before showing anything beyond a local demo.

## Demo Flow for Interview

1. Show the architecture diagram in `docs/architecture.md`.
2. Explain how CSV data lands in `data/sample_sales.csv`.
3. Run validation with `etl/validate_sales.py`.
4. Load data into PostgreSQL using `etl/load_sales.py`.
5. Explain trigger/function logic in `sql/02_procedures.sql`.
6. Show the GitLab pipeline in `.gitlab-ci.yml`.
7. Explain how you would deploy it cheaply on EC2 using `docs/aws-free-tier-deploy.md`.
8. Explain why EKS is production-relevant but not free-tier-friendly.

## Suggested Superset Charts

- Daily gross sales
- Daily refunds
- Net revenue by product
- Top 5 products by quantity
- Data quality failures by date

## Cleanup

```bash
docker compose down -v
```

If deployed on AWS, also terminate EC2 and delete unused EBS volumes, Elastic IPs, snapshots, and logs if no longer needed.
