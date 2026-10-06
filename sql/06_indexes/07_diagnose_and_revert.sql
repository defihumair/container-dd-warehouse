USE dd_warehouse;
GO

SELECT i.name AS index_name, i.type_desc,
       CAST(SUM(ps.reserved_page_count) * 8 / 1024.0 AS DECIMAL(10, 1)) AS reserved_mb
FROM sys.indexes AS i
JOIN sys.dm_db_partition_stats AS ps ON ps.object_id = i.object_id AND ps.index_id = i.index_id
WHERE i.object_id = OBJECT_ID(N'dw.fact_container_event')
GROUP BY i.name, i.type_desc
ORDER BY reserved_mb DESC;

SELECT state_desc AS rowgroup_state, COUNT(*) AS rowgroups, SUM(total_rows) AS total_rows,
       SUM(deleted_rows) AS deleted_rows,
       CAST(SUM(size_in_bytes) / 1048576.0 AS DECIMAL(10, 1)) AS size_mb
FROM sys.dm_db_column_store_row_group_physical_stats
WHERE object_id = OBJECT_ID(N'dw.fact_container_event')
GROUP BY state_desc;
GO

DROP INDEX IF EXISTS ix_fce_booking_event_type ON dw.fact_container_event;
DROP INDEX IF EXISTS cci_fact_container_event ON dw.fact_container_event;
GO

SELECT CAST(SUM(reserved_page_count) * 8 / 1024.0 AS DECIMAL(10, 1)) AS fact_table_mb_after_revert
FROM sys.dm_db_partition_stats
WHERE object_id = OBJECT_ID(N'dw.fact_container_event');

DECLARE @t0 DATETIME2, @n INT, @format_ms INT, @convert_ms INT, @r INT = 1;
DECLARE @f TABLE (run_no INT, format_ms INT, convert_ms INT);
WHILE @r <= 3
BEGIN
    SET @t0 = SYSDATETIME();
    SELECT @n = COUNT(DISTINCT FORMAT(event_ts, 'yyyyMMdd')) FROM dw.fact_container_event;
    SET @format_ms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
    SET @t0 = SYSDATETIME();
    SELECT @n = COUNT(DISTINCT CONVERT(CHAR(8), event_ts, 112)) FROM dw.fact_container_event;
    SET @convert_ms = DATEDIFF(MILLISECOND, @t0, SYSDATETIME());
    INSERT INTO @f VALUES (@r, @format_ms, @convert_ms);
    SET @r += 1;
END;
SELECT run_no, format_ms, convert_ms FROM @f ORDER BY run_no;
GO

EXEC dw.load_dd_charge;
EXEC dq.run_checks;
GO

SELECT check_name, failed_rows, status
FROM dq.check_result
WHERE dq_run_id = (SELECT MAX(dq_run_id) FROM dq.check_result)
  AND severity = N'error';
GO
