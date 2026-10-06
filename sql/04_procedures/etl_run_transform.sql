USE dd_warehouse;
GO

CREATE OR ALTER PROCEDURE etl.run_transform
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @run_id INT;

    INSERT INTO etl.run_log (step_name, start_ts, status)
    VALUES (N'etl.run_transform', SYSUTCDATETIME(), N'running');
    SET @run_id = SCOPE_IDENTITY();

    BEGIN TRY
        EXEC stg.load_reference_data;
        EXEC stg.load_container_event;
        EXEC dw.load_dimensions;
        EXEC dw.load_fact_container_event;
        EXEC dq.run_checks @fail_on_error = 1;
        EXEC dw.load_dd_charge;

        UPDATE etl.run_log
        SET end_ts = SYSUTCDATETIME(), status = N'success'
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
