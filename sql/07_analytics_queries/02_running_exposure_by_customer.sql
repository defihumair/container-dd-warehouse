-- Question: How does D&D exposure build up month by month for the five largest customers?
-- Technique: running total with SUM() OVER (ORDER BY ... ROWS UNBOUNDED PRECEDING)
-- Result: one row per customer per month with running total and share of the customer's total

USE dd_warehouse;
GO

WITH monthly AS (
    SELECT c.customer_name, d.year_month, SUM(f.charge_usd) AS month_usd
    FROM dw.fact_dd_charge AS f
    JOIN dw.dim_customer AS c ON c.customer_sk = f.customer_sk
    JOIN dw.dim_date AS d ON d.date_key = f.date_key
    GROUP BY c.customer_name, d.year_month
),
top5 AS (
    SELECT TOP (5) customer_name
    FROM monthly
    GROUP BY customer_name
    ORDER BY SUM(month_usd) DESC
)
SELECT m.customer_name, m.year_month, m.month_usd,
       SUM(m.month_usd) OVER (PARTITION BY m.customer_name ORDER BY m.year_month
                              ROWS UNBOUNDED PRECEDING) AS running_usd,
       CAST(100.0 * SUM(m.month_usd) OVER (PARTITION BY m.customer_name ORDER BY m.year_month
                                           ROWS UNBOUNDED PRECEDING)
            / SUM(m.month_usd) OVER (PARTITION BY m.customer_name) AS DECIMAL(5, 1)) AS pct_of_customer_total
FROM monthly AS m
JOIN top5 AS t ON t.customer_name = m.customer_name
ORDER BY m.customer_name, m.year_month;
GO
