CREATE TABLE IF NOT EXISTS raw_sales (
    sale_id BIGINT PRIMARY KEY,
    sale_date DATE NOT NULL,
    store TEXT NOT NULL,
    product TEXT NOT NULL,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(12, 2) NOT NULL CHECK (unit_price >= 0),
    refund_amount NUMERIC(12, 2) NOT NULL DEFAULT 0 CHECK (refund_amount >= 0),
    gross_amount NUMERIC(12, 2) GENERATED ALWAYS AS (quantity * unit_price) STORED,
    net_amount NUMERIC(12, 2) GENERATED ALWAYS AS ((quantity * unit_price) - refund_amount) STORED,
    loaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS etl_audit (
    audit_id BIGSERIAL PRIMARY KEY,
    job_name TEXT NOT NULL,
    status TEXT NOT NULL,
    rows_processed INTEGER NOT NULL DEFAULT 0,
    message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS data_quality_issues (
    issue_id BIGSERIAL PRIMARY KEY,
    source_file TEXT NOT NULL,
    sale_id TEXT,
    issue_type TEXT NOT NULL,
    issue_detail TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS daily_sales_summary (
    sale_date DATE PRIMARY KEY,
    total_orders INTEGER NOT NULL,
    gross_sales NUMERIC(14, 2) NOT NULL,
    refunds NUMERIC(14, 2) NOT NULL,
    net_sales NUMERIC(14, 2) NOT NULL,
    refreshed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_raw_sales_sale_date ON raw_sales (sale_date);
CREATE INDEX IF NOT EXISTS idx_raw_sales_product ON raw_sales (product);
CREATE INDEX IF NOT EXISTS idx_raw_sales_store_date ON raw_sales (store, sale_date);

