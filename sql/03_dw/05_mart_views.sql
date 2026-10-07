USE dd_warehouse;
GO

CREATE OR ALTER VIEW mart.v_dd_exposure
AS
SELECT f.container_no,
       f.booking_ref,
       f.cycle_no,
       f.charge_type,
       dc.container_type,
       dc.owner_type,
       c.customer_id,
       c.customer_name,
       c.segment,
       p.port_code,
       p.port_name,
       p.country,
       d.full_date AS start_date,
       d.year_month,
       f.charge_days,
       f.charge_usd,
       CAST(f.is_open AS INT) AS is_open,
       CASE WHEN f.charge_usd > 0 THEN 1 ELSE 0 END AS over_free_time,
       f.as_of_date
FROM dw.fact_dd_charge AS f
JOIN dw.dim_container AS dc ON dc.container_sk = f.container_sk
JOIN dw.dim_customer AS c ON c.customer_sk = f.customer_sk
JOIN dw.dim_port AS p ON p.port_sk = f.port_sk
JOIN dw.dim_date AS d ON d.date_key = f.date_key;
GO

CREATE OR ALTER VIEW mart.v_date
AS
SELECT d.date_key,
       d.full_date,
       d.day_of_month,
       d.day_name,
       CAST(d.is_weekend AS INT) AS is_weekend,
       d.month_no,
       d.month_name,
       d.year_month,
       d.quarter_no,
       d.year_no
FROM dw.dim_date AS d
WHERE d.date_key <> -1
  AND d.full_date >= (SELECT DATEFROMPARTS(YEAR(MIN(dd.full_date)), MONTH(MIN(dd.full_date)), 1)
                      FROM dw.fact_dd_charge AS f
                      JOIN dw.dim_date AS dd ON dd.date_key = f.date_key)
  AND d.full_date <= (SELECT EOMONTH(MAX(as_of_date)) FROM dw.fact_dd_charge);
GO

CREATE OR ALTER VIEW mart.v_dq_summary
AS
SELECT r.check_name,
       r.severity,
       r.failed_rows,
       r.threshold,
       r.status,
       r.run_ts
FROM dq.check_result AS r
WHERE r.dq_run_id = (SELECT MAX(dq_run_id) FROM dq.check_result);
GO

CREATE OR ALTER VIEW mart.v_quarantine_summary
AS
SELECT issue, COUNT(*) AS cycles
FROM dq.quarantine_cycle
GROUP BY issue;
GO

SELECT 'mart.v_dd_exposure' AS view_name, COUNT(*) AS row_count, SUM(charge_usd) AS total_usd FROM mart.v_dd_exposure
UNION ALL
SELECT 'mart.v_date', COUNT(*), NULL FROM mart.v_date
UNION ALL
SELECT 'mart.v_dq_summary', COUNT(*), NULL FROM mart.v_dq_summary
UNION ALL
SELECT 'mart.v_quarantine_summary', SUM(cycles), NULL FROM mart.v_quarantine_summary;

SELECT year_month, SUM(charge_usd) AS total_usd
FROM mart.v_dd_exposure
GROUP BY year_month
ORDER BY year_month;
GO
