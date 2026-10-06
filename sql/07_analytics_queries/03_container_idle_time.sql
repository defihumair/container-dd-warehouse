-- Question: How long do empty containers sit idle between gate-in (GTIN) and their next load (LOAD)?
-- Technique: LEAD() to look at each container's next event, GROUPING SETS for a total row
-- Result: 217,315 idle periods; average 8.50 days, maximum 17.07 days (ALL row).
--         Idle time is flat across ports (8.49-8.61) because the generator uses one idle rule for all ports.
USE dd_warehouse;
GO

WITH ev AS (
    SELECT dc.container_no, p.port_code, f.event_type, f.event_ts,
           LEAD(f.event_type) OVER (PARTITION BY dc.container_no ORDER BY f.event_ts, f.event_id) AS next_type,
           LEAD(f.event_ts)   OVER (PARTITION BY dc.container_no ORDER BY f.event_ts, f.event_id) AS next_ts
    FROM dw.fact_container_event AS f
    JOIN dw.dim_container AS dc ON dc.container_sk = f.container_sk
    JOIN dw.dim_port AS p ON p.port_sk = f.port_sk
    WHERE f.container_sk <> -1
),
idle AS (
    SELECT port_code, DATEDIFF(MINUTE, event_ts, next_ts) / 1440.0 AS idle_days
    FROM ev
    WHERE event_type = N'GTIN' AND next_type = N'LOAD'
)
SELECT ISNULL(port_code, N'ALL')                AS port_code,
       COUNT(*)                                 AS idle_periods,
       CAST(AVG(idle_days) AS DECIMAL(6, 2))    AS avg_idle_days,
       CAST(MAX(idle_days) AS DECIMAL(6, 2))    AS max_idle_days
FROM idle
GROUP BY GROUPING SETS ((port_code), ())
ORDER BY GROUPING(port_code) DESC, avg_idle_days DESC;
GO
