USE dd_warehouse;
GO

EXEC dq.run_checks;
GO

SELECT check_name, severity, failed_rows, threshold, status
FROM dq.check_result
WHERE dq_run_id = (SELECT MAX(dq_run_id) FROM dq.check_result)
ORDER BY CASE severity WHEN N'error' THEN 0 ELSE 1 END, check_id;

SELECT issue, COUNT(*) AS cycles
FROM dq.quarantine_cycle
GROUP BY issue
UNION ALL
SELECT N'TOTAL', COUNT(*) FROM dq.quarantine_cycle;

IF OBJECT_ID('tempdb..#manifest') IS NOT NULL DROP TABLE #manifest;
CREATE TABLE #manifest (event_id NVARCHAR(20), error_type NVARCHAR(30));
BULK INSERT #manifest FROM '/data/_validation/errors_manifest.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, ROWTERMINATOR = '0x0d0a');

SELECT N'duplicate_event' AS injected_error,
       (SELECT COUNT(DISTINCT event_id) FROM #manifest WHERE error_type = 'duplicate_event') AS injected,
       (SELECT COUNT(DISTINCT r.event_id) FROM stg.rejected_event AS r
        JOIN #manifest AS m ON m.event_id = r.event_id AND m.error_type = 'duplicate_event'
        WHERE r.reject_reason = N'duplicate in batch') AS detected,
       N'staging reject' AS caught_by
UNION ALL
SELECT N'invalid_timestamp',
       (SELECT COUNT(DISTINCT event_id) FROM #manifest WHERE error_type = 'invalid_timestamp'),
       (SELECT COUNT(DISTINCT r.event_id) FROM stg.rejected_event AS r
        JOIN #manifest AS m ON m.event_id = r.event_id AND m.error_type = 'invalid_timestamp'
        WHERE r.reject_reason = N'invalid timestamp'),
       N'staging reject'
UNION ALL
SELECT N'unknown_port',
       (SELECT COUNT(DISTINCT event_id) FROM #manifest WHERE error_type = 'unknown_port'),
       (SELECT COUNT(DISTINCT f.event_id) FROM dw.fact_container_event AS f
        JOIN #manifest AS m ON m.event_id = f.event_id AND m.error_type = 'unknown_port'
        WHERE f.port_sk = -1),
       N'dq check: facts with unknown port'
UNION ALL
SELECT N'bad_check_digit',
       (SELECT COUNT(DISTINCT event_id) FROM #manifest WHERE error_type = 'bad_check_digit'),
       (SELECT COUNT(DISTINCT s.event_id) FROM stg.container_event AS s
        JOIN #manifest AS m ON m.event_id = s.event_id AND m.error_type = 'bad_check_digit'
        WHERE dq.fn_is_valid_container_no(s.container_no) = 0),
       N'dq check: invalid container check digit'
UNION ALL
SELECT N'out_of_order',
       (SELECT COUNT(DISTINCT event_id) FROM #manifest WHERE error_type = 'out_of_order'),
       (SELECT COUNT(DISTINCT f.event_id) FROM dw.fact_container_event AS f
        JOIN #manifest AS m ON m.event_id = f.event_id AND m.error_type = 'out_of_order'
        JOIN dw.dim_container AS dc ON dc.container_sk = f.container_sk
        JOIN dq.quarantine_cycle AS q
          ON q.container_no = dc.container_no AND q.booking_ref = f.booking_ref
         AND q.issue = N'GTOT before DISC'),
       N'quarantine: GTOT before DISC'
UNION ALL
SELECT N'missing_gtin',
       (SELECT COUNT(DISTINCT event_id) FROM #manifest WHERE error_type = 'missing_gtin'),
       (SELECT failed_rows FROM dq.check_result
        WHERE check_name = N'GTOT with no GTIN after 60 days'
          AND dq_run_id = (SELECT MAX(dq_run_id) FROM dq.check_result)),
       N'dq check: GTOT with no GTIN after 60 days (indirect)';

SELECT TOP (3) run_id, step_name, rows_read AS checks_run, rows_rejected AS checks_failed, status, error_message,
       DATEDIFF(SECOND, start_ts, end_ts) AS seconds
FROM etl.run_log
ORDER BY run_id DESC;
GO
