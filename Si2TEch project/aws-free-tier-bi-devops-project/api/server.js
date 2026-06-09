require("dotenv").config({ path: "../.env" });

const express = require("express");
const { Pool } = require("pg");

const app = express();
const port = Number(process.env.API_PORT || 3000);

const pool = new Pool({
  host: process.env.POSTGRES_HOST || "localhost",
  port: Number(process.env.POSTGRES_PORT || 5432),
  database: process.env.POSTGRES_DB || "retailops",
  user: process.env.POSTGRES_USER || "retailops",
  password: process.env.POSTGRES_PASSWORD || "retailops_dev_password",
});

app.get("/health", async (request, response) => {
  const result = await pool.query("SELECT NOW() AS database_time");
  response.json({
    status: "ok",
    databaseTime: result.rows[0].database_time,
  });
});

app.get("/metrics/daily-sales", async (request, response) => {
  const result = await pool.query(
    "SELECT sale_date, total_orders, gross_sales, refunds, net_sales FROM daily_sales_summary ORDER BY sale_date"
  );
  response.json(result.rows);
});

app.get("/metrics/products", async (request, response) => {
  const result = await pool.query(
    "SELECT product, total_quantity, gross_sales, refunds, net_sales FROM vw_product_revenue ORDER BY net_sales DESC"
  );
  response.json(result.rows);
});

app.use((error, request, response, next) => {
  console.error(error);
  response.status(500).json({ error: "internal_server_error" });
});

app.listen(port, () => {
  console.log(`RetailOps BI API listening on port ${port}`);
});

