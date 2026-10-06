USE dd_warehouse;
GO

IF COL_LENGTH(N'dw.fact_dd_charge', N'booking_ref') IS NULL
    ALTER TABLE dw.fact_dd_charge ADD booking_ref NVARCHAR(20) NULL;
GO

CREATE OR ALTER PROCEDURE dw.load_dd_charge
    @as_of DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @run_id INT, @rows INT, @cycles INT, @excluded INT;

    IF @as_of IS NULL
        SET @as_of = (SELECT CAST(MAX(event_ts) AS DATE) FROM dw.fact_container_event);

    INSERT INTO etl.run_log (step_name, start_ts, status)
    VALUES (N'dw.load_dd_charge', SYSUTCDATETIME(), N'running');
    SET @run_id = SCOPE_IDENTITY();

    BEGIN TRY
        WITH ev AS (
            SELECT dc.container_no, dc.container_type, f.booking_ref, f.event_type, f.event_ts,
                   f.container_sk, f.customer_sk, f.port_sk
            FROM dw.fact_container_event AS f
            JOIN dw.dim_container AS dc ON dc.container_sk = f.container_sk
            WHERE f.container_sk <> -1
              AND f.event_type IN (N'DISC', N'GTOT', N'GTIN')
        ),
        bookings AS (
            SELECT container_no, booking_ref,
                   MIN(CASE WHEN event_type = N'DISC' THEN event_ts END)       AS disc_ts,
                   MIN(CASE WHEN event_type = N'GTOT' THEN event_ts END)       AS gtot_ts,
                   MIN(CASE WHEN event_type = N'GTIN' THEN event_ts END)       AS gtin_ts,
                   MAX(CASE WHEN event_type = N'DISC' THEN container_sk END)   AS container_sk,
                   MAX(CASE WHEN event_type = N'DISC' THEN container_type END) AS container_type,
                   MAX(CASE WHEN event_type = N'DISC' THEN customer_sk END)    AS customer_sk,
                   MAX(CASE WHEN event_type = N'DISC' THEN port_sk END)        AS port_sk
            FROM ev
            GROUP BY container_no, booking_ref
        )
        SELECT b.*,
               CASE
                   WHEN b.disc_ts IS NULL THEN N'no DISC event'
                   WHEN b.gtot_ts < b.disc_ts
                     OR b.gtin_ts < b.gtot_ts
                     OR (b.gtin_ts IS NOT NULL AND b.gtot_ts IS NULL) THEN N'sequence error'
               END AS exclude_reason
        INTO #cycles
        FROM bookings AS b;

        SET @cycles = (SELECT COUNT(*) FROM #cycles);
        SET @excluded = (SELECT COUNT(*) FROM #cycles WHERE exclude_reason IS NOT NULL);

        BEGIN TRANSACTION;

        TRUNCATE TABLE dw.fact_dd_charge;

        WITH valid AS (
            SELECT c.*,
                   ROW_NUMBER() OVER (PARTITION BY c.container_no ORDER BY c.disc_ts) AS cycle_no
            FROM #cycles AS c
            WHERE c.exclude_reason IS NULL
        ),
        days AS (
            SELECT v.container_no, v.cycle_no, v.booking_ref, v.container_sk, v.customer_sk, v.port_sk,
                   v.container_type, N'DEMURRAGE' AS charge_type, CAST(v.disc_ts AS DATE) AS start_date,
                   DATEDIFF(DAY, v.disc_ts, ISNULL(v.gtot_ts, @as_of)) + 1 AS charge_days,
                   CASE WHEN v.gtot_ts IS NULL THEN 1 ELSE 0 END AS is_open
            FROM valid AS v
            UNION ALL
            SELECT v.container_no, v.cycle_no, v.booking_ref, v.container_sk, v.customer_sk, v.port_sk,
                   v.container_type, N'DETENTION', CAST(v.gtot_ts AS DATE),
                   DATEDIFF(DAY, v.gtot_ts, ISNULL(v.gtin_ts, @as_of)) + 1,
                   CASE WHEN v.gtin_ts IS NULL THEN 1 ELSE 0 END
            FROM valid AS v
            WHERE v.gtot_ts IS NOT NULL
        )
        INSERT INTO dw.fact_dd_charge
            (container_no, cycle_no, charge_type, booking_ref, container_sk, customer_sk, port_sk, date_key,
             charge_days, is_open, charge_usd, as_of_date)
        SELECT d.container_no, d.cycle_no, d.charge_type, d.booking_ref, d.container_sk,
               ISNULL(d.customer_sk, -1), ISNULL(d.port_sk, -1),
               CONVERT(INT, CONVERT(CHAR(8), d.start_date, 112)),
               d.charge_days, d.is_open,
               SUM(GREATEST(0, LEAST(d.charge_days, ISNULL(t.to_day, d.charge_days)) - t.from_day + 1) * t.rate_usd),
               @as_of
        FROM days AS d
        JOIN dw.dim_tariff_tier AS t
          ON t.charge_type = d.charge_type
         AND t.container_type = d.container_type
        GROUP BY d.container_no, d.cycle_no, d.charge_type, d.booking_ref, d.container_sk, d.customer_sk,
                 d.port_sk, d.start_date, d.charge_days, d.is_open;
        SET @rows = @@ROWCOUNT;

        COMMIT TRANSACTION;

        UPDATE etl.run_log
        SET end_ts = SYSUTCDATETIME(), rows_read = @cycles, rows_inserted = @rows, rows_rejected = @excluded,
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
