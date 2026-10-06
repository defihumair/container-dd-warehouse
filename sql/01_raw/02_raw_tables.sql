USE dd_warehouse;
GO

IF OBJECT_ID(N'raw.container_event', N'U') IS NULL
CREATE TABLE raw.container_event (
    raw_id       BIGINT IDENTITY PRIMARY KEY,
    event_id     NVARCHAR(100) NULL,
    container_no NVARCHAR(100) NULL,
    event_type   NVARCHAR(100) NULL,
    event_ts     NVARCHAR(100) NULL,
    port_code    NVARCHAR(100) NULL,
    booking_ref  NVARCHAR(100) NULL,
    voyage_no    NVARCHAR(100) NULL,
    source_file  NVARCHAR(260) NOT NULL,
    loaded_at    DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

IF OBJECT_ID(N'raw.port', N'U') IS NULL
CREATE TABLE raw.port (
    port_code   NVARCHAR(100) NULL,
    port_name   NVARCHAR(100) NULL,
    country     NVARCHAR(100) NULL,
    source_file NVARCHAR(260) NULL,
    loaded_at   DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

IF OBJECT_ID(N'raw.customer', N'U') IS NULL
CREATE TABLE raw.customer (
    customer_id   NVARCHAR(100) NULL,
    customer_name NVARCHAR(100) NULL,
    segment       NVARCHAR(100) NULL,
    source_file   NVARCHAR(260) NULL,
    loaded_at     DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

IF OBJECT_ID(N'raw.vessel', N'U') IS NULL
CREATE TABLE raw.vessel (
    vessel_id   NVARCHAR(100) NULL,
    vessel_name NVARCHAR(100) NULL,
    imo_no      NVARCHAR(100) NULL,
    source_file NVARCHAR(260) NULL,
    loaded_at   DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

IF OBJECT_ID(N'raw.container', N'U') IS NULL
CREATE TABLE raw.container (
    container_no   NVARCHAR(100) NULL,
    container_type NVARCHAR(100) NULL,
    owner_type     NVARCHAR(100) NULL,
    effective_date NVARCHAR(100) NULL,
    source_file    NVARCHAR(260) NULL,
    loaded_at      DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

IF OBJECT_ID(N'raw.container_change', N'U') IS NULL
CREATE TABLE raw.container_change (
    container_no   NVARCHAR(100) NULL,
    container_type NVARCHAR(100) NULL,
    owner_type     NVARCHAR(100) NULL,
    effective_date NVARCHAR(100) NULL,
    source_file    NVARCHAR(260) NULL,
    loaded_at      DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

IF OBJECT_ID(N'raw.voyage', N'U') IS NULL
CREATE TABLE raw.voyage (
    voyage_no        NVARCHAR(100) NULL,
    vessel_id        NVARCHAR(100) NULL,
    origin_port      NVARCHAR(100) NULL,
    destination_port NVARCHAR(100) NULL,
    departure_ts     NVARCHAR(100) NULL,
    arrival_ts       NVARCHAR(100) NULL,
    source_file      NVARCHAR(260) NULL,
    loaded_at        DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

IF OBJECT_ID(N'raw.shipment', N'U') IS NULL
CREATE TABLE raw.shipment (
    booking_ref      NVARCHAR(100) NULL,
    customer_id      NVARCHAR(100) NULL,
    container_no     NVARCHAR(100) NULL,
    voyage_no        NVARCHAR(100) NULL,
    origin_port      NVARCHAR(100) NULL,
    destination_port NVARCHAR(100) NULL,
    source_file      NVARCHAR(260) NULL,
    loaded_at        DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

IF OBJECT_ID(N'raw.tariff_tier', N'U') IS NULL
CREATE TABLE raw.tariff_tier (
    charge_type    NVARCHAR(100) NULL,
    container_type NVARCHAR(100) NULL,
    from_day       NVARCHAR(100) NULL,
    to_day         NVARCHAR(100) NULL,
    rate_usd       NVARCHAR(100) NULL,
    source_file    NVARCHAR(260) NULL,
    loaded_at      DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO
