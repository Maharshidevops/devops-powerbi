CREATE OR REPLACE VIEW vw_product_revenue AS
SELECT
    product,
    SUM(quantity) AS total_quantity,
    SUM(gross_amount) AS gross_sales,
    SUM(refund_amount) AS refunds,
    SUM(net_amount) AS net_sales
FROM raw_sales
GROUP BY product;

CREATE OR REPLACE VIEW vw_store_daily_sales AS
SELECT
    store,
    sale_date,
    COUNT(*) AS total_orders,
    SUM(net_amount) AS net_sales
FROM raw_sales
GROUP BY store, sale_date;

