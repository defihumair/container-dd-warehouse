USE dd_warehouse;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE object_id = OBJECT_ID(N'dw.fact_container_event') AND name = N'cci_fact_container_event')
    CREATE CLUSTERED COLUMNSTORE INDEX cci_fact_container_event ON dw.fact_container_event;
GO

EXEC etl.run_benchmark @label = N'B columnstore';
GO
