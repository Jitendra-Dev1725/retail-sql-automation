# Retail SQL Automation (Week 5 – Automation and Integration of SQL Processes)

Stored procedures, triggers and scheduled events that automate routine
operations of a simulated retail database (MySQL 8.0.16+).

## What is automated

| Process | Mechanism | Schedule |
|---|---|---|
| Order entry with stock check | `sp_place_order` (transaction + row lock) | on demand |
| Stock deduction / cancel restock | triggers on `order_items`, `orders` | real time |
| Low-stock alert + auto-resolve | trigger on `products` | real time |
| Price-change audit | trigger on `products` | real time |
| Alert → purchase request | `sp_create_purchase_requests` | hourly (at :30) |
| Receive supplier stock | `sp_receive_purchase` | on demand |
| Daily sales summary (reporting layer) | `sp_refresh_daily_sales_summary` | nightly 01:00 |
| Dynamic reports | `sp_dynamic_sales_report`, `sp_top_products`, `v_inventory_status` | on demand |
| Archive old orders | `sp_archive_old_orders` (batched) | monthly |
| Log clean-up | event `ev_weekly_log_cleanup` | weekly |

## How to run

```bash
mysql -u root -p < sql/01_schema.sql
mysql -u root -p < sql/02_sample_data.sql
mysql -u root -p < sql/03_sp_place_order.sql
mysql -u root -p < sql/04_triggers.sql
mysql -u root -p < sql/05_sp_purchasing.sql
mysql -u root -p < sql/06_sp_reporting.sql
mysql -u root -p < sql/07_sp_archive.sql
mysql -u root -p < sql/08_scheduled_events.sql
mysql -u root -p --force < sql/09_test_script.sql   # end-to-end tests (tests 2 and 4 fail on purpose)
```

`sql/10_security.sql` creates least-privilege accounts (change the passwords first).
`sql/11_monitoring_and_performance.sql` has morning health checks and EXPLAIN examples.

## Folder layout

```
sql/        numbered scripts (run in order)
diagrams/   flowcharts used in the report (PNG)
docs/       Week5_Automation_Report.docx
```
