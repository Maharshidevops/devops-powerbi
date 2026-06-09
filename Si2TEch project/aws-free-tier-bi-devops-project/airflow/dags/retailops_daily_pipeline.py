from datetime import datetime
from pathlib import Path

from airflow import DAG
from airflow.operators.bash import BashOperator


PROJECT_ROOT = Path("/opt/airflow/project")


with DAG(
    dag_id="retailops_daily_pipeline",
    description="Validate and load retail sales data for BI reporting.",
    start_date=datetime(2026, 6, 1),
    schedule="@daily",
    catchup=False,
    tags=["bi", "retailops", "postgres"],
) as dag:
    validate_sales = BashOperator(
        task_id="validate_sales_csv",
        bash_command=f"cd {PROJECT_ROOT} && python etl/validate_sales.py data/sample_sales.csv",
    )

    load_sales = BashOperator(
        task_id="load_sales_to_postgres",
        bash_command=f"cd {PROJECT_ROOT} && python etl/load_sales.py data/sample_sales.csv",
    )

    validate_sales >> load_sales

