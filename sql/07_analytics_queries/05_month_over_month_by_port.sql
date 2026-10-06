-- Question: How did D&D charges change month over month at each discharge port?
-- Technique: CTE + LAG() window function
-- Note: December 2025 is a partial first month and June 2026 is cut at the as-of date
-- Result: every port rises from January to a March peak, then falls through June.
--         Largest increase: BEANR in 2026-02, +296.5% vs January. AEJEA peaked at 1,684,815 USD in 2026-03.
--         Note: January is low because containers start their first cycle during the first 30 days,
--         and June is cut at the 2026-06-29 as-of date.

USE dd_warehouse;
GO

WITH monthly AS (
    SELECT p.port_code, d.year_month, SUM(f.charge_usd) AS dd_usd
    FROM dw.fact_dd_charge AS f
    JOIN dw.dim_port AS p ON p.port_sk = f.port_sk
    JOIN dw.dim_date AS d ON d.date_key = f.date_key
    WHERE f.port_sk <> -1
    GROUP BY p.port_code, d.year_month
)
SELECT port_code, year_month, dd_usd,
       LAG(dd_usd) OVER (PARTITION BY port_code ORDER BY year_month) AS prev_month_usd,
       dd_usd - LAG(dd_usd) OVER (PARTITION BY port_code ORDER BY year_month) AS change_usd,
       CAST(100.0 * (dd_usd - LAG(dd_usd) OVER (PARTITION BY port_code ORDER BY year_month))
            / NULLIF(LAG(dd_usd) OVER (PARTITION BY port_code ORDER BY year_month), 0) AS DECIMAL(7, 1)) AS change_pct
FROM monthly
ORDER BY port_code, year_month;
GO
