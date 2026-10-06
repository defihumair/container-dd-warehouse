USE dd_warehouse;
GO

BEGIN TRANSACTION;
DELETE TOP (1) FROM dw.fact_container_event;
EXEC dq.run_checks;
GO

ROLLBACK TRANSACTION;
GO

SELECT COUNT(*) AS fact_rows_after_rollback FROM dw.fact_container_event;
GO
