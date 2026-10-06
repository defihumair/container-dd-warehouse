USE dd_warehouse;
GO

EXEC dw.load_dd_charge;
GO

SELECT charge_type,
       COUNT(*)                                       AS cycles,
       SUM(CAST(is_open AS INT))                      AS still_open,
       SUM(CASE WHEN charge_usd > 0 THEN 1 ELSE 0 END) AS over_free_time,
       SUM(charge_usd)                                AS total_usd,
       CAST(AVG(CAST(charge_days AS DECIMAL(10, 2))) AS DECIMAL(10, 2)) AS avg_days,
       MIN(charge_days)                               AS min_days,
       MAX(charge_days)                               AS max_days,
       MAX(as_of_date)                                AS as_of_date
FROM dw.fact_dd_charge
GROUP BY charge_type
ORDER BY charge_type;

WITH tiers AS (
    SELECT charge_type, container_type,
           MAX(CASE WHEN rate_usd = 0 THEN to_day END)                         AS free_days,
           MAX(CASE WHEN rate_usd > 0 AND to_day IS NOT NULL THEN to_day END)   AS tier2_end,
           MAX(CASE WHEN rate_usd > 0 AND to_day IS NOT NULL THEN rate_usd END) AS tier2_rate,
           MAX(CASE WHEN to_day IS NULL THEN rate_usd END)                      AS tier3_rate
    FROM dw.dim_tariff_tier
    GROUP BY charge_type, container_type
)
SELECT COUNT(*) AS rows_checked,
       SUM(CASE WHEN f.charge_usd <>
                     CASE WHEN f.charge_days <= t.free_days THEN 0
                          WHEN f.charge_days <= t.tier2_end THEN (f.charge_days - t.free_days) * t.tier2_rate
                          ELSE (t.tier2_end - t.free_days) * t.tier2_rate
                               + (f.charge_days - t.tier2_end) * t.tier3_rate
                     END
                THEN 1 ELSE 0 END) AS mismatches_vs_independent_formula
FROM dw.fact_dd_charge AS f
JOIN dw.dim_container AS dc ON dc.container_sk = f.container_sk
JOIN tiers AS t ON t.charge_type = f.charge_type AND t.container_type = dc.container_type;

SELECT x.test_case, x.expected_usd, f.charge_days, f.charge_usd,
       CASE WHEN f.charge_usd = x.expected_usd THEN 'PASS' ELSE 'FAIL' END AS result
FROM (VALUES
        ('20DC demurrage, 12 days: 5 free + 5 x 40 + 2 x 80', N'DEMURRAGE', N'20DC', 12, 360.00),
        ('40HC demurrage, 8 days: 5 free + 3 x 70',          N'DEMURRAGE', N'40HC', 8,  210.00),
        ('40RF detention, 20 days: 7 free + 7 x 100 + 6 x 200', N'DETENTION', N'40RF', 20, 1900.00)
     ) AS x (test_case, charge_type, container_type, charge_days, expected_usd)
CROSS APPLY (
    SELECT TOP (1) fc.charge_days, fc.charge_usd
    FROM dw.fact_dd_charge AS fc
    JOIN dw.dim_container AS dc ON dc.container_sk = fc.container_sk
    WHERE fc.charge_type = x.charge_type
      AND dc.container_type = x.container_type
      AND fc.charge_days = x.charge_days
) AS f;

IF OBJECT_ID('tempdb..#chronic') IS NOT NULL DROP TABLE #chronic;
CREATE TABLE #chronic (customer_id NVARCHAR(20));
BULK INSERT #chronic FROM '/data/_validation/chronic_customers.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, ROWTERMINATOR = '0x0d0a');

SELECT TOP (10) c.customer_id, c.customer_name,
       CAST(AVG(CAST(f.charge_days AS DECIMAL(10, 2))) AS DECIMAL(10, 1)) AS avg_detention_days,
       SUM(f.charge_usd) AS detention_usd,
       CASE WHEN ch.customer_id IS NOT NULL THEN 'planted late returner' ELSE '' END AS answer_key
FROM dw.fact_dd_charge AS f
JOIN dw.dim_customer AS c ON c.customer_sk = f.customer_sk
LEFT JOIN #chronic AS ch ON ch.customer_id = c.customer_id
WHERE f.charge_type = N'DETENTION' AND f.is_open = 0
GROUP BY c.customer_id, c.customer_name, ch.customer_id
ORDER BY avg_detention_days DESC;

SELECT TOP (3) run_id, step_name, rows_read AS cycles_found, rows_inserted AS charge_rows,
       rows_rejected AS cycles_excluded, status, DATEDIFF(SECOND, start_ts, end_ts) AS seconds
FROM etl.run_log
ORDER BY run_id DESC;
GO
