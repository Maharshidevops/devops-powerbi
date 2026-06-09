import csv
import sys
from datetime import datetime
from decimal import Decimal, InvalidOperation
from pathlib import Path


REQUIRED_COLUMNS = {
    "sale_id",
    "sale_date",
    "store",
    "product",
    "quantity",
    "unit_price",
    "refund_amount",
}


def validate_row(row, row_number):
    errors = []

    if not row.get("sale_id", "").strip().isdigit():
        errors.append("sale_id must be numeric")

    try:
        datetime.strptime(row.get("sale_date", ""), "%Y-%m-%d")
    except ValueError:
        errors.append("sale_date must use YYYY-MM-DD")

    if not row.get("store", "").strip():
        errors.append("store is required")

    if not row.get("product", "").strip():
        errors.append("product is required")

    try:
        quantity = int(row.get("quantity", ""))
        if quantity <= 0:
            errors.append("quantity must be greater than zero")
    except ValueError:
        errors.append("quantity must be an integer")

    for money_field in ("unit_price", "refund_amount"):
        try:
            value = Decimal(row.get(money_field, ""))
            if value < 0:
                errors.append(f"{money_field} cannot be negative")
        except InvalidOperation:
            errors.append(f"{money_field} must be numeric")

    return [f"row {row_number}: {error}" for error in errors]


def validate_file(csv_path):
    errors = []
    seen_sale_ids = set()

    with Path(csv_path).open(newline="", encoding="utf-8") as sales_file:
        reader = csv.DictReader(sales_file)
        missing_columns = REQUIRED_COLUMNS - set(reader.fieldnames or [])
        if missing_columns:
            return [f"missing columns: {', '.join(sorted(missing_columns))}"]

        for row_number, row in enumerate(reader, start=2):
            sale_id = row.get("sale_id", "").strip()
            if sale_id in seen_sale_ids:
                errors.append(f"row {row_number}: duplicate sale_id {sale_id}")
            seen_sale_ids.add(sale_id)
            errors.extend(validate_row(row, row_number))

    return errors


def main():
    csv_path = sys.argv[1] if len(sys.argv) > 1 else "data/sample_sales.csv"
    errors = validate_file(csv_path)

    if errors:
        print("Data validation failed:")
        for error in errors:
            print(f"- {error}")
        raise SystemExit(1)

    print(f"Data validation passed for {csv_path}")


if __name__ == "__main__":
    main()

