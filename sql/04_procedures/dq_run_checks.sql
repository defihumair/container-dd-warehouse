USE dd_warehouse;
GO

CREATE OR ALTER PROCEDURE dq.run_checks
    @as_of         DATE = NULL,
    @fail_on_error BIT  = 1
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @run_id INT, @now DATETIME2 = SYSUTCDATETIME(), @checks INT, @failed INT, @error_fails INT;

    IF @as_of IS NULL
        SET @as_of = (SELECT CAST(MAX(event_ts) AS DATE) FROM dw.fact_container_event);

    INSERT INTO etl.run_log (step_name, start_ts, status)
    VALUES (N'dq.run_checks', @now, N'running');
    SET @run_id = SCOPE_IDENTITY();

    BEGIN TRY
        WITH bookings AS (
            SELECT dc.container_no, f.booking_ref,
                   MIN(CASE WHEN f.event_type = N'DISC' THEN f.event_ts END) AS disc_ts,
                   MIN(CASE WHEN f.event_type = N'GTOT' THEN f.event_ts END) AS gtot_ts,
                   MIN(CASE WHEN f.event_type = N'GTIN' THEN f.event_ts END) AS gtin_ts
            FROM dw.fact_container_event AS f
            JOIN dw.dim_container AS dc ON dc.container_sk = f.container_sk
            WHERE f.container_sk <> -1
              AND f.event_type IN (N'DISC', N'GTOT', N'GTIN')
            GROUP BY dc.container_no, f.booking_ref
        )
        SELECT b.*,
               CASE
                   WHEN b.disc_ts IS NULL THEN N'no DISC event'
                   WHEN b.gtot_ts < b.disc_ts THEN N'GTOT before DISC'
                   WHEN b.gtin_ts < b.gtot_ts THEN N'GTIN before GTOT'
                   WHEN b.gtin_ts IS NOT NULL AND b.gtot_ts IS NULL THEN N'GTIN without GTOT'
               END AS issue
        INTO #bookings
        FROM bookings AS b;

        BEGIN TRANSACTION;

        TRUNCATE TABLE dq.quarantine_cycle;
        INSERT INTO dq.quarantine_cycle (container_no, booking_ref, issue, disc_ts, gtot_ts, gtin_ts)
        SELECT container_no, booking_ref, issue, disc_ts, gtot_ts, gtin_ts
        FROM #bookings
        WHERE issue IS NOT NULL;

        INSERT INTO dq.check_result (dq_run_id, run_ts, check_name, severity, failed_rows, threshold, status)
        SELECT @run_id, @now, c.check_name, c.severity, c.failed_rows, c.threshold, N'pending'
        FROM (
            SELECT N'raw = staging + rejected' AS check_name, N'error' AS severity,
                   ABS((SELECT COUNT(*) FROM raw.container_event)
                       - (SELECT COUNT(*) FROM stg.container_event)
                       - (SELECT COUNT(*) FROM stg.rejected_event)) AS failed_rows,
                   0 AS threshold
            UNION ALL
            SELECT N'staging = warehouse fact', N'error',
                   ABS((SELECT COUNT(*) FROM stg.container_event)
                       - (SELECT COUNT(*) FROM dw.fact_container_event)), 0
            UNION ALL
            SELECT N'duplicate event_id in fact', N'error',
                   (SELECT COUNT(*) - COUNT(DISTINCT event_id) FROM dw.fact_container_event), 0
            UNION ALL
            SELECT N'charge days below 1', N'error',
                   (SELECT COUNT(*) FROM dw.fact_dd_charge WHERE charge_days < 1), 0
            UNION ALL
            SELECT N'charge vs independent formula', N'error',
                   (SELECT COUNT(*)
                    FROM dw.fact_dd_charge AS f
                    JOIN dw.dim_container AS dc ON dc.container_sk = f.container_sk
                    JOIN (
                        SELECT charge_type, container_type,
                               MAX(CASE WHEN rate_usd = 0 THEN to_day END)                         AS free_days,
                               MAX(CASE WHEN rate_usd > 0 AND to_day IS NOT NULL THEN to_day END)   AS tier2_end,
                               MAX(CASE WHEN rate_usd > 0 AND to_day IS NOT NULL THEN rate_usd END) AS tier2_rate,
                               MAX(CASE WHEN to_day IS NULL THEN rate_usd END)                      AS tier3_rate
                        FROM dw.dim_tariff_tier
                        GROUP BY charge_type, container_type
                    ) AS t ON t.charge_type = f.charge_type AND t.container_type = dc.container_type
                    WHERE f.charge_usd <>
                          CASE WHEN f.charge_days <= t.free_days THEN 0
                               WHEN f.charge_days <= t.tier2_end THEN (f.charge_days - t.free_days) * t.tier2_rate
                               ELSE (t.tier2_end - t.free_days) * t.tier2_rate
                                    + (f.charge_days - t.tier2_end) * t.tier3_rate
                          END), 0
            UNION ALL
            SELECT N'rows rejected in staging', N'warning',
                   (SELECT COUNT(*) FROM stg.rejected_event),
                   (SELECT CAST(COUNT(*) * 0.02 AS INT) FROM raw.container_event)
            UNION ALL
            SELECT N'facts with unknown port', N'warning',
                   (SELECT COUNT(*) FROM dw.fact_container_event WHERE port_sk = -1), 0
            UNION ALL
            SELECT N'events with invalid container check digit', N'warning',
                   (SELECT ISNULL(SUM(x.events), 0)
                    FROM (SELECT container_no, COUNT(*) AS events
                          FROM stg.container_event
                          GROUP BY container_no) AS x
                    WHERE dq.fn_is_valid_container_no(x.container_no) = 0), 0
            UNION ALL
            SELECT N'cycles quarantined: no DISC event', N'warning',
                   (SELECT COUNT(*) FROM #bookings WHERE issue = N'no DISC event'), 0
            UNION ALL
            SELECT N'cycles quarantined: GTOT before DISC', N'warning',
                   (SELECT COUNT(*) FROM #bookings WHERE issue = N'GTOT before DISC'), 0
            UNION ALL
            SELECT N'cycles quarantined: GTIN without GTOT', N'warning',
                   (SELECT COUNT(*) FROM #bookings WHERE issue = N'GTIN without GTOT'), 0
            UNION ALL
            SELECT N'DISC with no GTOT after 60 days', N'warning',
                   (SELECT COUNT(*) FROM #bookings
                    WHERE issue IS NULL AND gtot_ts IS NULL AND gtin_ts IS NULL
                      AND CAST(disc_ts AS DATE) <= DATEADD(DAY, -60, @as_of)), 0
            UNION ALL
            SELECT N'GTOT with no GTIN after 60 days', N'warning',
                   (SELECT COUNT(*) FROM #bookings
                    WHERE issue IS NULL AND gtot_ts IS NOT NULL AND gtin_ts IS NULL
                      AND CAST(gtot_ts AS DATE) <= DATEADD(DAY, -60, @as_of)), 0
            UNION ALL
            SELECT N'hours since last staging load', N'warning',
                   (SELECT ISNULL(DATEDIFF(HOUR, MAX(stg_loaded_at), SYSUTCDATETIME()), 0) FROM stg.container_event),
                   24
        ) AS c;

        UPDATE dq.check_result
        SET status = CASE WHEN failed_rows <= threshold THEN N'pass' ELSE N'fail' END
        WHERE dq_run_id = @run_id;

        COMMIT TRANSACTION;

        SELECT @checks      = COUNT(*),
               @failed      = SUM(CASE WHEN status = N'fail' THEN 1 ELSE 0 END),
               @error_fails = SUM(CASE WHEN status = N'fail' AND severity = N'error' THEN 1 ELSE 0 END)
        FROM dq.check_result
        WHERE dq_run_id = @run_id;

        UPDATE etl.run_log
        SET end_ts = SYSUTCDATETIME(), rows_read = @checks, rows_inserted = @checks - @failed,
            rows_rejected = @failed,
            status = CASE WHEN @error_fails > 0 THEN N'failed' ELSE N'success' END,
            error_message = CASE WHEN @error_fails > 0
                                 THEN CONCAT(@error_fails, N' error-level data quality check(s) failed') END
        WHERE run_id = @run_id;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        UPDATE etl.run_log
        SET end_ts = SYSUTCDATETIME(), status = N'failed', error_message = ERROR_MESSAGE()
        WHERE run_id = @run_id;
        THROW;
    END CATCH;

    IF @error_fails > 0 AND @fail_on_error = 1
        THROW 50010, 'Data quality: an error-level check failed. Pipeline stopped before the D&D calculation.', 1;
END;
GO
