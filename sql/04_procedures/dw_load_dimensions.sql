USE dd_warehouse;
GO

CREATE OR ALTER PROCEDURE dw.load_dimensions
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @run_id INT, @rows INT = 0, @scd2_changes INT = 0, @step_rows INT;

    INSERT INTO etl.run_log (step_name, start_ts, status)
    VALUES (N'dw.load_dimensions', SYSUTCDATETIME(), N'running');
    SET @run_id = SCOPE_IDENTITY();

    BEGIN TRY
        BEGIN TRANSACTION;

        WITH n AS (
            SELECT TOP (DATEDIFF(DAY, '2025-01-01', '2027-12-31') + 1)
                   ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS i
            FROM sys.all_objects AS a CROSS JOIN sys.all_objects AS b
        ),
        d AS (
            SELECT DATEADD(DAY, i, CAST('2025-01-01' AS DATE)) AS full_date FROM n
        )
        INSERT INTO dw.dim_date (date_key, full_date, day_of_month, day_name, is_weekend, week_of_year, month_no,
                                 month_name, year_month, quarter_no, year_no)
        SELECT CONVERT(INT, CONVERT(CHAR(8), d.full_date, 112)),
               d.full_date,
               DAY(d.full_date),
               DATENAME(WEEKDAY, d.full_date),
               CASE WHEN DATEPART(WEEKDAY, d.full_date) IN (1, 7) THEN 1 ELSE 0 END,
               DATEPART(ISO_WEEK, d.full_date),
               MONTH(d.full_date),
               DATENAME(MONTH, d.full_date),
               CONVERT(CHAR(7), d.full_date, 126),
               DATEPART(QUARTER, d.full_date),
               YEAR(d.full_date)
        FROM d
        WHERE NOT EXISTS (SELECT 1 FROM dw.dim_date AS x WHERE x.full_date = d.full_date);
        SET @rows += @@ROWCOUNT;

        MERGE dw.dim_port AS t
        USING stg.port AS s ON t.port_code = s.port_code
        WHEN MATCHED AND (t.port_name <> s.port_name OR t.country <> s.country) THEN
            UPDATE SET port_name = s.port_name, country = s.country, updated_at = SYSUTCDATETIME()
        WHEN NOT MATCHED BY TARGET THEN
            INSERT (port_code, port_name, country) VALUES (s.port_code, s.port_name, s.country);
        SET @rows += @@ROWCOUNT;

        MERGE dw.dim_customer AS t
        USING stg.customer AS s ON t.customer_id = s.customer_id
        WHEN MATCHED AND (t.customer_name <> s.customer_name OR t.segment <> s.segment) THEN
            UPDATE SET customer_name = s.customer_name, segment = s.segment, updated_at = SYSUTCDATETIME()
        WHEN NOT MATCHED BY TARGET THEN
            INSERT (customer_id, customer_name, segment) VALUES (s.customer_id, s.customer_name, s.segment);
        SET @rows += @@ROWCOUNT;

        MERGE dw.dim_vessel AS t
        USING stg.vessel AS s ON t.vessel_id = s.vessel_id
        WHEN MATCHED AND (t.vessel_name <> s.vessel_name OR t.imo_no <> s.imo_no) THEN
            UPDATE SET vessel_name = s.vessel_name, imo_no = s.imo_no, updated_at = SYSUTCDATETIME()
        WHEN NOT MATCHED BY TARGET THEN
            INSERT (vessel_id, vessel_name, imo_no) VALUES (s.vessel_id, s.vessel_name, s.imo_no);
        SET @rows += @@ROWCOUNT;

        MERGE dw.dim_tariff_tier AS t
        USING stg.tariff_tier AS s
           ON t.charge_type = s.charge_type AND t.container_type = s.container_type AND t.from_day = s.from_day
        WHEN MATCHED AND (ISNULL(t.to_day, -1) <> ISNULL(s.to_day, -1) OR t.rate_usd <> s.rate_usd) THEN
            UPDATE SET to_day = s.to_day, rate_usd = s.rate_usd, updated_at = SYSUTCDATETIME()
        WHEN NOT MATCHED BY TARGET THEN
            INSERT (charge_type, container_type, from_day, to_day, rate_usd)
            VALUES (s.charge_type, s.container_type, s.from_day, s.to_day, s.rate_usd);
        SET @rows += @@ROWCOUNT;

        INSERT INTO dw.dim_container (container_no, container_type, owner_type, valid_from, valid_to, is_current)
        SELECT s.container_no, s.container_type, s.owner_type, s.effective_date, NULL, 1
        FROM stg.container AS s
        WHERE NOT EXISTS (SELECT 1 FROM dw.dim_container AS d WHERE d.container_no = s.container_no);
        SET @rows += @@ROWCOUNT;

        WHILE 1 = 1
        BEGIN
            DROP TABLE IF EXISTS #next_change;

            WITH pending AS (
                SELECT c.container_no, c.container_type, c.owner_type, c.effective_date,
                       ROW_NUMBER() OVER (PARTITION BY c.container_no ORDER BY c.effective_date) AS rn
                FROM stg.container_change AS c
                JOIN dw.dim_container AS d
                  ON d.container_no = c.container_no
                 AND d.is_current = 1
                WHERE c.effective_date > d.valid_from
                  AND (c.container_type <> d.container_type OR c.owner_type <> d.owner_type)
            )
            SELECT container_no, container_type, owner_type, effective_date
            INTO #next_change
            FROM pending
            WHERE rn = 1;

            SET @step_rows = @@ROWCOUNT;
            IF @step_rows = 0 BREAK;

            UPDATE d
            SET d.valid_to = n.effective_date, d.is_current = 0
            FROM dw.dim_container AS d
            JOIN #next_change AS n ON n.container_no = d.container_no
            WHERE d.is_current = 1;

            INSERT INTO dw.dim_container (container_no, container_type, owner_type, valid_from, valid_to, is_current)
            SELECT container_no, container_type, owner_type, effective_date, NULL, 1
            FROM #next_change;

            SET @scd2_changes += @step_rows;
        END;

        SET @rows += @scd2_changes;

        COMMIT TRANSACTION;

        UPDATE etl.run_log
        SET end_ts = SYSUTCDATETIME(), rows_read = @scd2_changes, rows_inserted = @rows, rows_rejected = 0,
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
