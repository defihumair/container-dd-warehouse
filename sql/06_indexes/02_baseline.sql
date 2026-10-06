USE dd_warehouse;
GO

EXEC etl.run_benchmark @label = N'0 baseline';
GO
