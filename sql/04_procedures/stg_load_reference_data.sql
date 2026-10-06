USE dd_warehouse;
GO

CREATE OR ALTER PROCEDURE stg.load_reference_data
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @run_id INT, @rows INT = 0;

    INSERT INTO etl.run_log (step_name, start_ts, status)
    VALUES (N'stg.load_reference_data', SYSUTCDATETIME(), N'running');
    SET @run_id = SCOPE_IDENTITY();

    BEGIN TRY
        BEGIN TRANSACTION;

        TRUNCATE TABLE stg.port;
        INSERT INTO stg.port (port_code, port_name, country)
        SELECT UPPER(TRIM(port_code)), TRIM(port_name), UPPER(TRIM(country))
        FROM raw.port;
        SET @rows += @@ROWCOUNT;

        TRUNCATE TABLE stg.customer;
        INSERT INTO stg.customer (customer_id, customer_name, segment)
        SELECT UPPER(TRIM(customer_id)), TRIM(customer_name), TRIM(segment)
        FROM raw.customer;
        SET @rows += @@ROWCOUNT;

        TRUNCATE TABLE stg.vessel;
        INSERT INTO stg.vessel (vessel_id, vessel_name, imo_no)
        SELECT UPPER(TRIM(vessel_id)), TRIM(vessel_name), TRIM(imo_no)
        FROM raw.vessel;
        SET @rows += @@ROWCOUNT;

        TRUNCATE TABLE stg.container;
        INSERT INTO stg.container (container_no, container_type, owner_type, effective_date)
        SELECT UPPER(TRIM(container_no)), UPPER(TRIM(container_type)), UPPER(TRIM(owner_type)),
               CONVERT(DATE, TRIM(effective_date), 23)
        FROM raw.container;
        SET @rows += @@ROWCOUNT;

        TRUNCATE TABLE stg.container_change;
        INSERT INTO stg.container_change (container_no, container_type, owner_type, effective_date)
        SELECT UPPER(TRIM(container_no)), UPPER(TRIM(container_type)), UPPER(TRIM(owner_type)),
               CONVERT(DATE, TRIM(effective_date), 23)
        FROM raw.container_change;
        SET @rows += @@ROWCOUNT;

        TRUNCATE TABLE stg.voyage;
        INSERT INTO stg.voyage (voyage_no, vessel_id, origin_port, destination_port, departure_ts, arrival_ts)
        SELECT UPPER(TRIM(voyage_no)), UPPER(TRIM(vessel_id)), UPPER(TRIM(origin_port)), UPPER(TRIM(destination_port)),
               CONVERT(DATETIME2(0), TRIM(departure_ts), 120), CONVERT(DATETIME2(0), TRIM(arrival_ts), 120)
        FROM raw.voyage;
        SET @rows += @@ROWCOUNT;

        TRUNCATE TABLE stg.shipment;
        INSERT INTO stg.shipment (booking_ref, customer_id, container_no, voyage_no, origin_port, destination_port)
        SELECT UPPER(TRIM(booking_ref)), UPPER(TRIM(customer_id)), UPPER(TRIM(container_no)), UPPER(TRIM(voyage_no)),
               UPPER(TRIM(origin_port)), UPPER(TRIM(destination_port))
        FROM raw.shipment;
        SET @rows += @@ROWCOUNT;

        TRUNCATE TABLE stg.tariff_tier;
        INSERT INTO stg.tariff_tier (charge_type, container_type, from_day, to_day, rate_usd)
        SELECT UPPER(TRIM(charge_type)), UPPER(TRIM(container_type)), CONVERT(INT, TRIM(from_day)),
               TRY_CONVERT(INT, NULLIF(TRIM(to_day), N'')), CONVERT(DECIMAL(10, 2), TRIM(rate_usd))
        FROM raw.tariff_tier;
        SET @rows += @@ROWCOUNT;

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
