USE dd_warehouse;
GO

EXEC dw.load_fact_container_event;
GO

SELECT 'stg.container_event' AS check_name, COUNT(*) AS result FROM stg.container_event
UNION ALL SELECT 'dw.fact_container_event', COUNT(*) FROM dw.fact_container_event
UNION ALL SELECT 'stg minus fact (rows lost)',
    (SELECT COUNT(*) FROM stg.container_event) - (SELECT COUNT(*) FROM dw.fact_container_event)
UNION ALL SELECT 'facts with unknown container', COUNT(*) FROM dw.fact_container_event WHERE container_sk = -1
UNION ALL SELECT 'facts with unknown port', COUNT(*) FROM dw.fact_container_event WHERE port_sk = -1
UNION ALL SELECT 'facts with unknown customer', COUNT(*) FROM dw.fact_container_event WHERE customer_sk = -1
UNION ALL SELECT 'facts with unknown vessel', COUNT(*) FROM dw.fact_container_event WHERE vessel_sk = -1
UNION ALL SELECT 'late-arriving events loaded',
    COUNT(*)
    FROM dw.fact_container_event AS f
    JOIN stg.container_event AS s ON s.event_id = f.event_id
    WHERE CAST(f.event_ts AS DATE) < CAST(SUBSTRING(s.source_file, 8, 10) AS DATE);

SELECT event_type, COUNT(*) AS events
FROM dw.fact_container_event
GROUP BY event_type
ORDER BY event_type;

SELECT f.event_type, f.event_ts, dc.owner_type, dc.valid_from, dc.valid_to
FROM dw.fact_container_event AS f
JOIN dw.dim_container AS dc ON dc.container_sk = f.container_sk
WHERE dc.container_no = N'DDXU0010654'
ORDER BY f.event_ts;

SELECT table_name, last_loaded_ts FROM etl.watermark;

SELECT TOP (3) run_id, step_name, rows_read, rows_inserted, status,
       DATEDIFF(SECOND, start_ts, end_ts) AS seconds
FROM etl.run_log
ORDER BY run_id DESC;
GO
