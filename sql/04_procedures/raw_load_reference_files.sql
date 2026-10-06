USE dd_warehouse;
GO

CREATE OR ALTER PROCEDURE raw.load_reference_file
    @table_name SYSNAME,
    @file_name  NVARCHAR(260)
AS
BEGIN
    SET NOCOUNT ON;

    IF @table_name NOT IN (N'port', N'customer', N'vessel', N'container', N'container_change',
                           N'voyage', N'shipment', N'tariff_tier')
        THROW 50002, 'Unknown reference table.', 1;

    IF @file_name LIKE N'%[^a-z_.]%'
        THROW 50003, 'Reference file name may contain only letters, underscores and dots.', 1;

    DECLARE @run_id INT, @rows INT, @cols NVARCHAR(MAX), @sql NVARCHAR(MAX);

    INSERT INTO etl.run_log (step_name, start_ts, status)
    VALUES (CONCAT(N'raw.load_reference_file:', @table_name), SYSUTCDATETIME(), N'running');
    SET @run_id = SCOPE_IDENTITY();

    BEGIN TRY
        SELECT @cols = STRING_AGG(QUOTENAME(c.name), N', ') WITHIN GROUP (ORDER BY c.column_id)
        FROM sys.columns AS c
        WHERE c.object_id = OBJECT_ID(N'raw.' + QUOTENAME(@table_name))
          AND c.name NOT IN (N'source_file', N'loaded_at');

        SET @sql =
            N'TRUNCATE TABLE raw.' + QUOTENAME(@table_name) + N';' +
            N' SELECT TOP (0) ' + @cols + N' INTO #landing FROM raw.' + QUOTENAME(@table_name) + N';' +
            N' BULK INSERT #landing FROM ''/data/ref/' + @file_name +
            N''' WITH (FORMAT = ''CSV'', FIRSTROW = 2, ROWTERMINATOR = ''0x0d0a'');' +
            N' INSERT INTO raw.' + QUOTENAME(@table_name) + N' (' + @cols + N', source_file)' +
            N' SELECT ' + @cols + N', @file FROM #landing;' +
            N' SET @row_count = @@ROWCOUNT;';

        EXEC sp_executesql @sql,
             N'@file NVARCHAR(260), @row_count INT OUTPUT',
             @file = @file_name, @row_count = @rows OUTPUT;

        UPDATE etl.run_log
        SET end_ts = SYSUTCDATETIME(), rows_read = @rows, rows_inserted = @rows, rows_rejected = 0,
            status = N'success'
        WHERE run_id = @run_id;
    END TRY
    BEGIN CATCH
        UPDATE etl.run_log
        SET end_ts = SYSUTCDATETIME(), status = N'failed', error_message = ERROR_MESSAGE()
        WHERE run_id = @run_id;
        THROW;
    END CATCH
END;
GO

CREATE OR ALTER PROCEDURE raw.load_all_reference_files
AS
BEGIN
    SET NOCOUNT ON;
    EXEC raw.load_reference_file @table_name = N'port',             @file_name = N'ports.csv';
    EXEC raw.load_reference_file @table_name = N'customer',         @file_name = N'customers.csv';
    EXEC raw.load_reference_file @table_name = N'vessel',           @file_name = N'vessels.csv';
    EXEC raw.load_reference_file @table_name = N'container',        @file_name = N'containers.csv';
    EXEC raw.load_reference_file @table_name = N'container_change', @file_name = N'container_changes.csv';
    EXEC raw.load_reference_file @table_name = N'voyage',           @file_name = N'voyages.csv';
    EXEC raw.load_reference_file @table_name = N'shipment',         @file_name = N'shipments.csv';
    EXEC raw.load_reference_file @table_name = N'tariff_tier',      @file_name = N'tariff_tiers.csv';
END;
GO
