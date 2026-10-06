USE dd_warehouse;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE object_id = OBJECT_ID(N'dw.fact_container_event') AND name = N'ix_fce_booking_event_type')
    CREATE INDEX ix_fce_booking_event_type
        ON dw.fact_container_event (booking_ref, event_type)
        INCLUDE (event_ts, container_sk);
GO

EXEC etl.run_benchmark @label = N'C booking index';
GO
