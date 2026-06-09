import csv
import sys
from pathlib import Path

from db import get_connection
from validate_sales import validate_file


SQL_FILES = [
    "sql/01_schema.sql",
    "sql/02_procedures.sql",
    "sql/03_views.sql",
]


def execute_sql_files(connection):
    with connection.cursor() as cursor:
        for sql_file in SQL_FILES:
            cursor.execute(Path(sql_file).read_text(encoding="utf-8"))
    connection.commit()


def load_sales(connection, csv_path):
    rows_processed = 0

    with Path(csv_path).open(newline="", encoding="utf-8") as sales_file:
        reader = csv.DictReader(sales_file)
        with connection.cursor() as cursor:
            for row in reader:
                cursor.execute(
                    """
                    INSERT INTO raw_sales (
                        sale_id,
                        sale_date,
                        store,
                        product,
                        quantity,
                        unit_price,
                        refund_amount
                    )
                    VALUES (%s, %s, %s, %s, %s, %s, %s)
                    ON CONFLICT (sale_id)
                    DO UPDATE SET
                        sale_date = EXCLUDED.sale_date,
                        store = EXCLUDED.store,
                        product = EXCLUDED.product,
                        quantity = EXCLUDED.quantity,
                        unit_price = EXCLUDED.unit_price,
                        refund_amount = EXCLUDED.refund_amount,
                        loaded_at = NOW();
                    """,
                    (
                        row["sale_id"],
                        row["sale_date"],
                        row["store"],
                        row["product"],
                        row["quantity"],
                        row["unit_price"],
                        row["refund_amount"],
                    ),
                )
                rows_processed += 1

            cursor.execute("SELECT refresh_daily_sales_summary();")
            cursor.execute(
                """
                INSERT INTO etl_audit (job_name, status, rows_processed, message)
                VALUES (%s, %s, %s, %s);
                """,
                ("load_sales", "SUCCESS", rows_processed, f"Loaded {csv_path}"),
            )

    connection.commit()
    return rows_processed


def main():
    csv_path = sys.argv[1] if len(sys.argv) > 1 else "data/sample_sales.csv"
    errors = validate_file(csv_path)

    if errors:
        for error in errors:
            print(error)
        raise SystemExit(1)

    with get_connection() as connection:
        execute_sql_files(connection)
        rows_processed = load_sales(connection, csv_path)

    print(f"Loaded {rows_processed} sales rows from {csv_path}")


if __name__ == "__main__":
    main()

