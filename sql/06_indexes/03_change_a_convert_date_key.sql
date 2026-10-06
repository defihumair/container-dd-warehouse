USE dd_warehouse;
GO

EXEC etl.run_benchmark @label = N'A convert date_key';
GO
