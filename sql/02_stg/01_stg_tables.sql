USE dd_warehouse;
GO

IF OBJECT_ID(N'stg.container_event', N'U') IS NULL
CREATE TABLE stg.container_event (
    stg_id        BIGINT IDENTITY PRIMARY KEY,
    raw_id        BIGINT NOT NULL,
    event_id      NVARCHAR(20) NOT NULL,
    container_no  NVARCHAR(20) NOT NULL,
    event_type    NVARCHAR(4) NOT NULL,
    event_ts      DATETIME2(0) NOT NULL,
    port_code     NVARCHAR(10) NULL,
    booking_ref   NVARCHAR(20) NULL,
    voyage_no     NVARCHAR(40) NULL,
    source_file   NVARCHAR(260) NOT NULL,
    stg_loaded_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ux_stg_container_event_event_id')
CREATE UNIQUE INDEX ux_stg_container_event_event_id ON stg.container_event (event_id);
GO

IF OBJECT_ID(N'stg.rejected_event', N'U') IS NULL
CREATE TABLE stg.rejected_event (
    reject_id     BIGINT IDENTITY PRIMARY KEY,
    raw_id        BIGINT NOT NULL,
    event_id      NVARCHAR(100) NULL,
    container_no  NVARCHAR(100) NULL,
    event_type    NVARCHAR(100) NULL,
    event_ts      NVARCHAR(100) NULL,
    port_code     NVARCHAR(100) NULL,
    booking_ref   NVARCHAR(100) NULL,
    voyage_no     NVARCHAR(100) NULL,
    source_file   NVARCHAR(260) NOT NULL,
    reject_reason NVARCHAR(50) NOT NULL,
    rejected_at   DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

IF OBJECT_ID(N'stg.port', N'U') IS NULL
CREATE TABLE stg.port (
    port_code NVARCHAR(10) NOT NULL PRIMARY KEY,
    port_name NVARCHAR(100) NOT NULL,
    country   NCHAR(2) NOT NULL
);
GO

IF OBJECT_ID(N'stg.customer', N'U') IS NULL
CREATE TABLE stg.customer (
    customer_id   NVARCHAR(20) NOT NULL PRIMARY KEY,
    customer_name NVARCHAR(100) NOT NULL,
    segment       NVARCHAR(50) NOT NULL
);
GO

IF OBJECT_ID(N'stg.vessel', N'U') IS NULL
CREATE TABLE stg.vessel (
    vessel_id   NVARCHAR(20) NOT NULL PRIMARY KEY,
    vessel_name NVARCHAR(100) NOT NULL,
    imo_no      NCHAR(7) NOT NULL
);
GO

IF OBJECT_ID(N'stg.container', N'U') IS NULL
CREATE TABLE stg.container (
    container_no   NVARCHAR(11) NOT NULL PRIMARY KEY,
    container_type NVARCHAR(10) NOT NULL,
    owner_type     NVARCHAR(10) NOT NULL,
    effective_date DATE NOT NULL
);
GO

IF OBJECT_ID(N'stg.container_change', N'U') IS NULL
CREATE TABLE stg.container_change (
    container_no   NVARCHAR(11) NOT NULL,
    container_type NVARCHAR(10) NOT NULL,
    owner_type     NVARCHAR(10) NOT NULL,
    effective_date DATE NOT NULL,
    CONSTRAINT pk_stg_container_change PRIMARY KEY (container_no, effective_date)
);
GO

IF OBJECT_ID(N'stg.voyage', N'U') IS NULL
CREATE TABLE stg.voyage (
    voyage_no        NVARCHAR(40) NOT NULL PRIMARY KEY,
    vessel_id        NVARCHAR(20) NOT NULL,
    origin_port      NVARCHAR(10) NOT NULL,
    destination_port NVARCHAR(10) NOT NULL,
    departure_ts     DATETIME2(0) NOT NULL,
    arrival_ts       DATETIME2(0) NOT NULL
);
GO

IF OBJECT_ID(N'stg.shipment', N'U') IS NULL
CREATE TABLE stg.shipment (
    booking_ref      NVARCHAR(20) NOT NULL PRIMARY KEY,
    customer_id      NVARCHAR(20) NOT NULL,
    container_no     NVARCHAR(11) NOT NULL,
    voyage_no        NVARCHAR(40) NOT NULL,
    origin_port      NVARCHAR(10) NOT NULL,
    destination_port NVARCHAR(10) NOT NULL
);
GO

IF OBJECT_ID(N'stg.tariff_tier', N'U') IS NULL
CREATE TABLE stg.tariff_tier (
    charge_type    NVARCHAR(10) NOT NULL,
    container_type NVARCHAR(10) NOT NULL,
    from_day       INT NOT NULL,
    to_day         INT NULL,
    rate_usd       DECIMAL(10, 2) NOT NULL,
    CONSTRAINT pk_stg_tariff_tier PRIMARY KEY (charge_type, container_type, from_day)
);
GO
