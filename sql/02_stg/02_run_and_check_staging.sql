USE dd_warehouse;
GO

EXEC stg.load_reference_data;
EXEC stg.load_container_event;
GO

SELECT 'raw.container_event' AS check_name, COUNT(*) AS row_count FROM raw.container_event
UNION ALL SELECT 'stg.container_event', COUNT(*) FROM stg.container_event
UNION ALL SELECT 'stg.rejected_event', COUNT(*) FROM stg.rejected_event
UNION ALL SELECT 'raw minus (stg + rejected)',
    (SELECT COUNT(*) FROM raw.container_event)
    - (SELECT COUNT(*) FROM stg.container_event)
    - (SELECT COUNT(*) FROM stg.rejected_event);

SELECT reject_reason, COUNT(*) AS rows_rejected
FROM stg.rejected_event
GROUP BY reject_reason
ORDER BY rows_rejected DESC;

IF OBJECT_ID('tempdb..#manifest') IS NOT NULL DROP TABLE #manifest;
CREATE TABLE #manifest (event_id NVARCHAR(20), error_type NVARCHAR(30));
BULK INSERT #manifest FROM '/data/_validation/errors_manifest.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, ROWTERMINATOR = '0x0d0a');

SELECT m.error_type,
       COUNT(DISTINCT m.event_id) AS injected_event_ids,
       COUNT(DISTINCT r.event_id) AS caught_in_staging
FROM #manifest AS m
LEFT JOIN stg.rejected_event AS r
       ON r.event_id = m.event_id
      AND r.reject_reason = CASE m.error_type
                                WHEN 'invalid_timestamp' THEN N'invalid timestamp'
                                WHEN 'duplicate_event'   THEN N'duplicate in batch'
                            END
WHERE m.error_type IN ('invalid_timestamp', 'duplicate_event')
GROUP BY m.error_type;

SELECT table_name, last_raw_id FROM etl.watermark;

SELECT TOP (5) run_id, step_name, rows_read, rows_inserted, rows_rejected, status,
       DATEDIFF(SECOND, start_ts, end_ts) AS seconds
FROM etl.run_log
ORDER BY run_id DESC;
GO
