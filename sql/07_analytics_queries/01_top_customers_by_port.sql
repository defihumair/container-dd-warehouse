-- Question: Which customers drive the most D&D charges at each discharge port?
-- Technique: CTE + RANK() window function
-- Result: top 3 customers per port (45 rows); paste the first rows here after running

USE dd_warehouse;
GO

WITH customer_port AS (
    SELECT p.port_code, p.port_name, c.customer_name,
           SUM(f.charge_usd) AS dd_usd,
           COUNT(*)          AS charge_rows
    FROM dw.fact_dd_charge AS f
    JOIN dw.dim_port AS p ON p.port_sk = f.port_sk
    JOIN dw.dim_customer AS c ON c.customer_sk = f.customer_sk
    WHERE f.port_sk <> -1
    GROUP BY p.port_code, p.port_name, c.customer_name
),
ranked AS (
    SELECT cp.*,
           RANK() OVER (PARTITION BY cp.port_code ORDER BY cp.dd_usd DESC) AS rnk
    FROM customer_port AS cp
)
SELECT port_code, port_name, rnk, customer_name, dd_usd, charge_rows
FROM ranked
WHERE rnk <= 3
ORDER BY port_code, rnk;
GO
