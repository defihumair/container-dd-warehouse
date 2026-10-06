USE dd_warehouse;
GO

CREATE OR ALTER PROCEDURE raw.load_event_file
    @file_name NVARCHAR(260)
AS
BEGIN
    SET NOCOUNT ON;

    IF @file_name NOT LIKE N'events[_][0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9].csv'
        THROW 50001, 'File name must match events_YYYY-MM-DD.csv', 1;

    IF EXISTS (SELECT 1 FROM etl.file_manifest WHERE file_name = @file_name)
        RETURN;

    DECLARE @run_id INT, @rows INT;

    INSERT INTO etl.run_log (step_name, start_ts, status)
    VALUES (N'raw.load_event_file', SYSUTCDATETIME(), N'running');
    SET @run_id = SCOPE_IDENTITY();

    BEGIN TRY
        CREATE TABLE #landing (
            event_id     NVARCHAR(100),
            container_no NVARCHAR(100),
            event_type   NVARCHAR(100),
            event_ts     NVARCHAR(100),
            port_code    NVARCHAR(100),
            booking_ref  NVARCHAR(100),
            voyage_no    NVARCHAR(100)
        );

        DECLARE @sql NVARCHAR(MAX) =
            N'BULK INSERT #landing FROM ''/data/events/' + @file_name +
            N''' WITH (FORMAT = ''CSV'', FIRSTROW = 2, ROWTERMINATOR = ''0x0d0a'');';
        EXEC sp_executesql @sql;

        BEGIN TRANSACTION;

        INSERT INTO raw.container_event
            (event_id, container_no, event_type, event_ts, port_code, booking_ref, voyage_no, source_file)
        SELECT event_id, container_no, event_type, event_ts, port_code, booking_ref, voyage_no, @file_name
        FROM #landing;
        SET @rows = @@ROWCOUNT;

        INSERT INTO etl.file_manifest (file_name, loaded_at, row_count)
        VALUES (@file_name, SYSUTCDATETIME(), @rows);

        COMMIT TRANSACTION;

        UPDATE etl.run_log
        SET end_ts = SYSUTCDATETIME(), rows_read = @rows, rows_inserted = @rows, rows_rejected = 0,
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
