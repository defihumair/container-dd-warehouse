USE dd_warehouse;
GO

WITH med AS (
    SELECT DISTINCT label, workload, unit,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY metric_value)
               OVER (PARTITION BY label, workload) AS median_value
    FROM etl.benchmark_result
)
SELECT workload, unit,
       CAST(MAX(CASE WHEN label = N'0 baseline'         THEN median_value END) AS DECIMAL(12, 1)) AS [0 baseline],
       CAST(MAX(CASE WHEN label = N'A convert date_key' THEN median_value END) AS DECIMAL(12, 1)) AS [A convert date_key],
       CAST(MAX(CASE WHEN label = N'B columnstore'      THEN median_value END) AS DECIMAL(12, 1)) AS [B columnstore],
       CAST(MAX(CASE WHEN label = N'C booking index'    THEN median_value END) AS DECIMAL(12, 1)) AS [C booking index]
FROM med
GROUP BY workload, unit
ORDER BY workload;
GO

EXEC dq.run_checks;
GO

SELECT check_name, failed_rows, status
FROM dq.check_result
WHERE dq_run_id = (SELECT MAX(dq_run_id) FROM dq.check_result)
  AND severity = N'error';
GO
