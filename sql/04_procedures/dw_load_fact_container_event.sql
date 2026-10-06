USE dd_warehouse;
GO

CREATE OR ALTER PROCEDURE dw.load_fact_container_event
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @run_id INT, @read INT, @before INT, @after INT, @merged INT;
    DECLARE @wm DATETIME2 =
        (SELECT ISNULL(last_loaded_ts, '1900-01-01') FROM etl.watermark
         WHERE table_name = N'dw.fact_container_event');
    DECLARE @new_wm DATETIME2 =
        (SELECT MAX(stg_loaded_at) FROM stg.container_event WHERE stg_loaded_at > @wm);

    INSERT INTO etl.run_log (step_name, start_ts, status)
    VALUES (N'dw.load_fact_container_event', SYSUTCDATETIME(), N'running');
    SET @run_id = SCOPE_IDENTITY();

    BEGIN TRY
        IF @new_wm IS NULL
        BEGIN
            UPDATE etl.run_log
            SET end_ts = SYSUTCDATETIME(), rows_read = 0, rows_inserted = 0, rows_rejected = 0, status = N'success'
            WHERE run_id = @run_id;
            RETURN;
        END;

        SET @read = (SELECT COUNT(*) FROM stg.container_event
                     WHERE stg_loaded_at > @wm AND stg_loaded_at <= @new_wm);
        SET @before = (SELECT COUNT(*) FROM dw.fact_container_event);

        BEGIN TRANSACTION;

        MERGE dw.fact_container_event AS t
        USING (
            SELECT e.event_id,
                   ISNULL(dc.container_sk, -1) AS container_sk,
                   ISNULL(dp.port_sk, -1)      AS port_sk,
                   ISNULL(cu.customer_sk, -1)  AS customer_sk,
                   ISNULL(dv.vessel_sk, -1)    AS vessel_sk,
                   CONVERT(INT, FORMAT(e.event_ts, 'yyyyMMdd')) AS date_key,
                   e.event_type, e.event_ts, e.booking_ref, e.voyage_no, e.stg_loaded_at
            FROM stg.container_event AS e
            LEFT JOIN dw.dim_container AS dc
                   ON dc.container_no = e.container_no
                  AND e.event_ts >= dc.valid_from
                  AND (dc.valid_to IS NULL OR e.event_ts < dc.valid_to)
            LEFT JOIN dw.dim_port AS dp ON dp.port_code = e.port_code
            LEFT JOIN stg.shipment AS sh ON sh.booking_ref = e.booking_ref
            LEFT JOIN dw.dim_customer AS cu ON cu.customer_id = sh.customer_id
            LEFT JOIN stg.voyage AS vo ON vo.voyage_no = e.voyage_no
            LEFT JOIN dw.dim_vessel AS dv ON dv.vessel_id = vo.vessel_id
            WHERE e.stg_loaded_at > @wm
              AND e.stg_loaded_at <= @new_wm
        ) AS s
        ON t.event_id = s.event_id
        WHEN MATCHED AND (t.event_ts <> s.event_ts OR t.event_type <> s.event_type
                          OR t.container_sk <> s.container_sk OR t.port_sk <> s.port_sk) THEN
            UPDATE SET container_sk = s.container_sk, port_sk = s.port_sk, customer_sk = s.customer_sk,
                       vessel_sk = s.vessel_sk, date_key = s.date_key, event_type = s.event_type,
                       event_ts = s.event_ts, booking_ref = s.booking_ref, voyage_no = s.voyage_no,
                       stg_loaded_at = s.stg_loaded_at, dw_loaded_at = SYSUTCDATETIME()
        WHEN NOT MATCHED BY TARGET THEN
            INSERT (event_id, container_sk, port_sk, customer_sk, vessel_sk, date_key, event_type, event_ts,
                    booking_ref, voyage_no, stg_loaded_at)
            VALUES (s.event_id, s.container_sk, s.port_sk, s.customer_sk, s.vessel_sk, s.date_key, s.event_type,
                    s.event_ts, s.booking_ref, s.voyage_no, s.stg_loaded_at);
        SET @merged = @@ROWCOUNT;

        UPDATE etl.watermark
        SET last_loaded_ts = @new_wm
        WHERE table_name = N'dw.fact_container_event';

        COMMIT TRANSACTION;

        SET @after = (SELECT COUNT(*) FROM dw.fact_container_event);

        UPDATE etl.run_log
        SET end_ts = SYSUTCDATETIME(), rows_read = @read, rows_inserted = @after - @before,
            rows_rejected = 0, status = N'success'
        WHERE run_id = @run_id;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        UPDATE etl.run_log
        SET end_ts = SYSUTCDATETIME(), status = N'failed', error_message = ERROR_MESSAGE()
        WHERE run_id = @run_id;
        THROW;
    END CATCH
END;
GO
