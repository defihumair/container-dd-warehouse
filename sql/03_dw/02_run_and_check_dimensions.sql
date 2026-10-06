USE dd_warehouse;
GO

EXEC dw.load_dimensions;
GO

SELECT 'dw.dim_date' AS table_name, COUNT(*) AS row_count FROM dw.dim_date
UNION ALL SELECT 'dw.dim_port', COUNT(*) FROM dw.dim_port
UNION ALL SELECT 'dw.dim_customer', COUNT(*) FROM dw.dim_customer
UNION ALL SELECT 'dw.dim_vessel', COUNT(*) FROM dw.dim_vessel
UNION ALL SELECT 'dw.dim_tariff_tier', COUNT(*) FROM dw.dim_tariff_tier
UNION ALL SELECT 'dw.dim_container (all versions)', COUNT(*) FROM dw.dim_container
UNION ALL SELECT 'dw.dim_container (current)', COUNT(*) FROM dw.dim_container WHERE is_current = 1
UNION ALL SELECT 'dw.dim_container (closed history)', COUNT(*) FROM dw.dim_container WHERE is_current = 0;

SELECT 'containers with 2+ versions' AS scd2_check, COUNT(*) AS result
FROM (SELECT container_no FROM dw.dim_container GROUP BY container_no HAVING COUNT(*) > 1) AS x
UNION ALL
SELECT 'containers with more than one current row', COUNT(*)
FROM (SELECT container_no FROM dw.dim_container WHERE is_current = 1 GROUP BY container_no HAVING COUNT(*) > 1) AS x
UNION ALL
SELECT 'closed rows where valid_to <= valid_from', COUNT(*)
FROM dw.dim_container WHERE is_current = 0 AND valid_to <= valid_from
UNION ALL
SELECT 'history gaps or overlaps', COUNT(*)
FROM (
    SELECT valid_to, LEAD(valid_from) OVER (PARTITION BY container_no ORDER BY valid_from) AS next_from
    FROM dw.dim_container
    WHERE container_sk <> -1
) AS h
WHERE h.next_from IS NOT NULL AND h.valid_to <> h.next_from;

SELECT container_sk, container_no, container_type, owner_type, valid_from, valid_to, is_current
FROM dw.dim_container
WHERE container_no = (SELECT TOP (1) container_no FROM dw.dim_container WHERE is_current = 0 ORDER BY container_no)
ORDER BY valid_from;

SELECT TOP (3) run_id, step_name, rows_read AS scd2_changes, rows_inserted, status,
       DATEDIFF(SECOND, start_ts, end_ts) AS seconds
FROM etl.run_log
ORDER BY run_id DESC;
GO
