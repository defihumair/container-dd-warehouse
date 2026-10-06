USE dd_warehouse;
GO

IF OBJECT_ID(N'etl.benchmark_result', N'U') IS NULL
CREATE TABLE etl.benchmark_result (
    benchmark_id INT IDENTITY PRIMARY KEY,
    label        NVARCHAR(60) NOT NULL,
    workload     NVARCHAR(60) NOT NULL,
    run_no       INT NOT NULL,
    metric_value DECIMAL(12, 2) NOT NULL,
    unit         NVARCHAR(10) NOT NULL,
    recorded_at  DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

CREATE OR ALTER PROCEDURE etl.run_benchmark
    @label NVARCHAR(60),
    @runs  INT = 3
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @i INT = 1, @t0 DATETIME2, @n INT, @avg DECIMAL(12, 4), @mb DECIMAL(12, 2);

    WHILE @i <= @runs
    BEGIN
        SET @t0 = SYSDATETIME();
        TRUNCATE TABLE dw.fact_container_event;
        UPDATE etl.watermark SET last_loaded_ts = NULL WHERE table_name = N'dw.fact_container_event';
        EXEC dw.load_fact_container_event;
        IF EXISTS (SELECT 1 FROM sys.indexes
                   WHERE object_id = OBJECT_ID(N'dw.fact_container_event') AND name = N'cci_fact_container_event')
            ALTER INDEX cci_fact_container_event ON dw.fact_container_event
                REORGANIZE WITH (COMPRESS_ALL_ROW_GROUPS = ON);
        INSERT INTO etl.benchmark_result (label, workload, run_no, metric_value, unit)
        VALUES (@label, N'1 fact load (full reload)', @i, DATEDIFF(MILLISECOND, @t0, SYSDATETIME()), N'ms');

        SET @t0 = SYSDATETIME();
        EXEC dw.load_dd_charge;
        INSERT INTO etl.benchmark_result (label, workload, run_no, metric_value, unit)
        VALUES (@label, N'2 D&D charge calculation', @i, DATEDIFF(MILLISECOND, @t0, SYSDATETIME()), N'ms');

        SET @t0 = SYSDATETIME();
        SELECT @n = COUNT(*)
        FROM dw.fact_container_event AS d
        WHERE d.event_type = N'DISC'
          AND d.container_sk <> -1
          AND EXISTS (SELECT 1 FROM dw.fact_container_event AS g
                      WHERE g.booking_ref = d.booking_ref AND g.container_sk = d.container_sk
                        AND g.event_type = N'GTOT' AND g.event_ts < d.event_ts);
        INSERT INTO etl.benchmark_result (label, workload, run_no, metric_value, unit)
        VALUES (@label, N'3 sequence check (EXISTS)', @i, DATEDIFF(MILLISECOND, @t0, SYSDATETIME()), N'ms');

        SET @t0 = SYSDATETIME();
        SELECT @avg = AVG(DATEDIFF(MINUTE, x.event_ts, x.next_ts) / 1440.0)
        FROM (
            SELECT f.event_type, f.event_ts,
                   LEAD(f.event_type) OVER (PARTITION BY dc.container_no ORDER BY f.event_ts, f.event_id) AS next_type,
                   LEAD(f.event_ts)   OVER (PARTITION BY dc.container_no ORDER BY f.event_ts, f.event_id) AS next_ts
            FROM dw.fact_container_event AS f
            JOIN dw.dim_container AS dc ON dc.container_sk = f.container_sk
            WHERE f.container_sk <> -1
        ) AS x
        WHERE x.event_type = N'GTIN' AND x.next_type = N'LOAD';
        INSERT INTO etl.benchmark_result (label, workload, run_no, metric_value, unit)
        VALUES (@label, N'4 idle time (LEAD)', @i, DATEDIFF(MILLISECOND, @t0, SYSDATETIME()), N'ms');

        SET @i += 1;
    END;

    SELECT @mb = SUM(reserved_page_count) * 8 / 1024.0
    FROM sys.dm_db_partition_stats
    WHERE object_id = OBJECT_ID(N'dw.fact_container_event');
    INSERT INTO etl.benchmark_result (label, workload, run_no, metric_value, unit)
    VALUES (@label, N'5 fact table size', 0, @mb, N'MB');
END;
GO
