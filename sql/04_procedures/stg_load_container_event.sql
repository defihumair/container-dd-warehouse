USE dd_warehouse;
GO

CREATE OR ALTER PROCEDURE stg.load_container_event
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @run_id INT, @read INT, @inserted INT, @rejected INT, @new_last_raw_id BIGINT;
    DECLARE @last_raw_id BIGINT =
        (SELECT ISNULL(last_raw_id, 0) FROM etl.watermark WHERE table_name = N'stg.container_event');

    INSERT INTO etl.run_log (step_name, start_ts, status)
    VALUES (N'stg.load_container_event', SYSUTCDATETIME(), N'running');
    SET @run_id = SCOPE_IDENTITY();

    BEGIN TRY
        WITH src AS (
            SELECT r.raw_id, r.source_file,
                   r.event_id AS raw_event_id, r.container_no AS raw_container_no,
                   r.event_type AS raw_event_type, r.event_ts AS raw_event_ts,
                   r.port_code AS raw_port_code, r.booking_ref AS raw_booking_ref, r.voyage_no AS raw_voyage_no,
                   UPPER(TRIM(r.event_id))                     AS event_id,
                   UPPER(TRIM(r.container_no))                 AS container_no,
                   UPPER(TRIM(r.event_type))                   AS event_type,
                   TRY_CONVERT(DATETIME2(0), TRIM(r.event_ts), 120) AS event_ts,
                   UPPER(TRIM(r.port_code))                    AS port_code,
                   UPPER(TRIM(r.booking_ref))                  AS booking_ref,
                   UPPER(TRIM(r.voyage_no))                    AS voyage_no,
                   ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(r.event_id)) ORDER BY r.raw_id) AS rn
            FROM raw.container_event AS r
            WHERE r.raw_id > @last_raw_id
        )
        SELECT src.*,
               CASE
                   WHEN src.event_id IS NULL OR src.event_id = N''
                     OR src.container_no IS NULL OR src.container_no = N'' THEN N'missing key'
                   WHEN src.event_ts IS NULL THEN N'invalid timestamp'
                   WHEN src.event_type NOT IN (N'LOAD', N'DISC', N'GTOT', N'GTIN') THEN N'invalid event type'
                   WHEN src.rn > 1 THEN N'duplicate in batch'
                   WHEN EXISTS (SELECT 1 FROM stg.container_event AS s WHERE s.event_id = src.event_id)
                       THEN N'duplicate of loaded event'
               END AS reject_reason
        INTO #checked
        FROM src;

        SET @read = (SELECT COUNT(*) FROM #checked);
        SET @new_last_raw_id = (SELECT MAX(raw_id) FROM #checked);

        BEGIN TRANSACTION;

        INSERT INTO stg.container_event
            (raw_id, event_id, container_no, event_type, event_ts, port_code, booking_ref, voyage_no, source_file)
        SELECT raw_id, event_id, container_no, event_type, event_ts, port_code, booking_ref, voyage_no, source_file
        FROM #checked
        WHERE reject_reason IS NULL;
        SET @inserted = @@ROWCOUNT;

        INSERT INTO stg.rejected_event
            (raw_id, event_id, container_no, event_type, event_ts, port_code, booking_ref, voyage_no,
             source_file, reject_reason)
        SELECT raw_id, raw_event_id, raw_container_no, raw_event_type, raw_event_ts, raw_port_code,
               raw_booking_ref, raw_voyage_no, source_file, reject_reason
        FROM #checked
        WHERE reject_reason IS NOT NULL;
        SET @rejected = @@ROWCOUNT;

        IF @new_last_raw_id IS NOT NULL
            UPDATE etl.watermark
            SET last_raw_id = @new_last_raw_id
            WHERE table_name = N'stg.container_event';

        COMMIT TRANSACTION;

        UPDATE etl.run_log
        SET end_ts = SYSUTCDATETIME(), rows_read = @read, rows_inserted = @inserted, rows_rejected = @rejected,
            status = N'success'
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
