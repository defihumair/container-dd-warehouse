USE dd_warehouse;
GO

EXEC raw.load_all_reference_files;
GO

DECLARE @d DATE = '2026-01-01', @file NVARCHAR(260);
WHILE @d < '2026-06-30'
BEGIN
    SET @file = CONCAT(N'events_', CONVERT(CHAR(10), @d, 23), N'.csv');
    EXEC raw.load_event_file @file_name = @file;
    SET @d = DATEADD(DAY, 1, @d);
END;
GO

SELECT 'raw.container_event' AS table_name, COUNT(*) AS row_count FROM raw.container_event
UNION ALL SELECT 'raw.port', COUNT(*) FROM raw.port
UNION ALL SELECT 'raw.customer', COUNT(*) FROM raw.customer
UNION ALL SELECT 'raw.vessel', COUNT(*) FROM raw.vessel
UNION ALL SELECT 'raw.container', COUNT(*) FROM raw.container
UNION ALL SELECT 'raw.container_change', COUNT(*) FROM raw.container_change
UNION ALL SELECT 'raw.voyage', COUNT(*) FROM raw.voyage
UNION ALL SELECT 'raw.shipment', COUNT(*) FROM raw.shipment
UNION ALL SELECT 'raw.tariff_tier', COUNT(*) FROM raw.tariff_tier
UNION ALL SELECT 'etl.file_manifest', COUNT(*) FROM etl.file_manifest;

SELECT step_name, status, COUNT(*) AS runs, SUM(rows_inserted) AS rows_inserted
FROM etl.run_log
GROUP BY step_name, status
ORDER BY step_name, status;
GO
