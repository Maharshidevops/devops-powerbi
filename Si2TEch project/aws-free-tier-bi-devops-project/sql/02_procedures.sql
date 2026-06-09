CREATE OR REPLACE FUNCTION refresh_daily_sales_summary()
RETURNS VOID
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO daily_sales_summary (
        sale_date,
        total_orders,
        gross_sales,
        refunds,
        net_sales,
        refreshed_at
    )
    SELECT
        sale_date,
        COUNT(*) AS total_orders,
        SUM(gross_amount) AS gross_sales,
        SUM(refund_amount) AS refunds,
        SUM(net_amount) AS net_sales,
        NOW() AS refreshed_at
    FROM raw_sales
    GROUP BY sale_date
    ON CONFLICT (sale_date)
    DO UPDATE SET
        total_orders = EXCLUDED.total_orders,
        gross_sales = EXCLUDED.gross_sales,
        refunds = EXCLUDED.refunds,
        net_sales = EXCLUDED.net_sales,
        refreshed_at = NOW();
END;
$$;

CREATE OR REPLACE FUNCTION write_raw_sales_audit()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO etl_audit (job_name, status, rows_processed, message)
    VALUES ('raw_sales_trigger', 'SUCCESS', 1, CONCAT('Loaded sale_id=', NEW.sale_id));

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_raw_sales_audit ON raw_sales;

CREATE TRIGGER trg_raw_sales_audit
AFTER INSERT ON raw_sales
FOR EACH ROW
EXECUTE FUNCTION write_raw_sales_audit();

