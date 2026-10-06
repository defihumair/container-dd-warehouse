-- Question: Which customers return containers late (over detention free time) several months in a row?
-- Technique: gaps-and-islands (month index minus ROW_NUMBER groups consecutive months)
-- Rule: a month counts when the customer has 10+ closed detention cycles and 75%+ of them exceed free time
-- Result: exactly 10 customers, each over free time for 6 consecutive months (2026-01 to 2026-06).
--         All 10 match the late returners planted by the generator (data/_validation/chronic_customers.csv).
USE dd_warehouse;
GO

WITH cycles AS (
    SELECT f.customer_sk, d.year_no * 12 + d.month_no - 1 AS month_index, d.year_month, f.charge_days
    FROM dw.fact_dd_charge AS f
    JOIN dw.dim_date AS d ON d.date_key = f.date_key
    WHERE f.charge_type = N'DETENTION' AND f.is_open = 0
),
monthly AS (
    SELECT customer_sk, month_index, MIN(year_month) AS year_month, COUNT(*) AS cycles,
           AVG(CASE WHEN charge_days > 7 THEN 1.0 ELSE 0.0 END) AS share_over_free_time
    FROM cycles
    GROUP BY customer_sk, month_index
),
flagged AS (
    SELECT m.*,
           m.month_index - ROW_NUMBER() OVER (PARTITION BY m.customer_sk ORDER BY m.month_index) AS island_id
    FROM monthly AS m
    WHERE m.cycles >= 10 AND m.share_over_free_time >= 0.75
),
islands AS (
    SELECT customer_sk, island_id,
           COUNT(*)        AS consecutive_months,
           MIN(year_month) AS from_month,
           MAX(year_month) AS to_month,
           CAST(AVG(share_over_free_time) * 100 AS DECIMAL(5, 1)) AS avg_pct_over_free_time
    FROM flagged
    GROUP BY customer_sk, island_id
)
SELECT c.customer_id, c.customer_name, i.consecutive_months, i.from_month, i.to_month, i.avg_pct_over_free_time
FROM islands AS i
JOIN dw.dim_customer AS c ON c.customer_sk = i.customer_sk
WHERE i.consecutive_months >= 3
ORDER BY i.consecutive_months DESC, i.avg_pct_over_free_time DESC;
GO
