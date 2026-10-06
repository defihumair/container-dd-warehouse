USE dd_warehouse;
GO

TRUNCATE TABLE dw.fact_dd_charge;
TRUNCATE TABLE dw.fact_container_event;
TRUNCATE TABLE dq.quarantine_cycle;

DELETE FROM dw.dim_container WHERE container_sk <> -1;
DELETE FROM dw.dim_port WHERE port_sk <> -1;
DELETE FROM dw.dim_customer WHERE customer_sk <> -1;
DELETE FROM dw.dim_vessel WHERE vessel_sk <> -1;
DELETE FROM dw.dim_tariff_tier;
DBCC CHECKIDENT (N'dw.dim_container', RESEED, 0) WITH NO_INFOMSGS;
DBCC CHECKIDENT (N'dw.dim_port', RESEED, 0) WITH NO_INFOMSGS;
DBCC CHECKIDENT (N'dw.dim_customer', RESEED, 0) WITH NO_INFOMSGS;
DBCC CHECKIDENT (N'dw.dim_vessel', RESEED, 0) WITH NO_INFOMSGS;
DBCC CHECKIDENT (N'dw.dim_tariff_tier', RESEED, 0) WITH NO_INFOMSGS;

TRUNCATE TABLE stg.container_event;
TRUNCATE TABLE stg.rejected_event;
TRUNCATE TABLE stg.port;
TRUNCATE TABLE stg.customer;
TRUNCATE TABLE stg.vessel;
TRUNCATE TABLE stg.container;
TRUNCATE TABLE stg.container_change;
TRUNCATE TABLE stg.voyage;
TRUNCATE TABLE stg.shipment;
TRUNCATE TABLE stg.tariff_tier;

TRUNCATE TABLE raw.container_event;
TRUNCATE TABLE raw.port;
TRUNCATE TABLE raw.customer;
TRUNCATE TABLE raw.vessel;
TRUNCATE TABLE raw.container;
TRUNCATE TABLE raw.container_change;
TRUNCATE TABLE raw.voyage;
TRUNCATE TABLE raw.shipment;
TRUNCATE TABLE raw.tariff_tier;

TRUNCATE TABLE etl.file_manifest;
UPDATE etl.watermark SET last_raw_id = NULL, last_loaded_ts = NULL;
GO

SELECT 'raw.container_event' AS table_name, COUNT(*) AS row_count FROM raw.container_event
UNION ALL SELECT 'stg.container_event', COUNT(*) FROM stg.container_event
UNION ALL SELECT 'dw.fact_container_event', COUNT(*) FROM dw.fact_container_event
UNION ALL SELECT 'dw.dim_container', COUNT(*) FROM dw.dim_container
UNION ALL SELECT 'etl.file_manifest', COUNT(*) FROM etl.file_manifest;
GO
