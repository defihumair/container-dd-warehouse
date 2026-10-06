USE dd_warehouse;
GO

IF OBJECT_ID(N'etl.run_log', N'U') IS NULL
CREATE TABLE etl.run_log (
    run_id        INT IDENTITY PRIMARY KEY,
    step_name     NVARCHAR(100) NOT NULL,
    start_ts      DATETIME2 NOT NULL,
    end_ts        DATETIME2 NULL,
    rows_read     INT NULL,
    rows_inserted INT NULL,
    rows_rejected INT NULL,
    status        NVARCHAR(20) NOT NULL,
    error_message NVARCHAR(4000) NULL
);
GO

IF OBJECT_ID(N'etl.file_manifest', N'U') IS NULL
CREATE TABLE etl.file_manifest (
    file_name NVARCHAR(260) PRIMARY KEY,
    loaded_at DATETIME2 NOT NULL,
    row_count INT NOT NULL
);
GO

IF OBJECT_ID(N'etl.watermark', N'U') IS NULL
CREATE TABLE etl.watermark (
    table_name     NVARCHAR(100) PRIMARY KEY,
    last_raw_id    BIGINT NULL,
    last_loaded_ts DATETIME2 NULL
);
GO

MERGE etl.watermark AS t
USING (VALUES (N'stg.container_event'), (N'dw.fact_container_event')) AS s (table_name)
ON t.table_name = s.table_name
WHEN NOT MATCHED THEN INSERT (table_name) VALUES (s.table_name);
GO
