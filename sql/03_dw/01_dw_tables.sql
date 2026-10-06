USE dd_warehouse;
GO

IF OBJECT_ID(N'dw.dim_date', N'U') IS NULL
CREATE TABLE dw.dim_date (
    date_key     INT NOT NULL PRIMARY KEY,
    full_date    DATE NOT NULL,
    day_of_month TINYINT NOT NULL,
    day_name     NVARCHAR(10) NOT NULL,
    is_weekend   BIT NOT NULL,
    week_of_year TINYINT NOT NULL,
    month_no     TINYINT NOT NULL,
    month_name   NVARCHAR(10) NOT NULL,
    year_month   CHAR(7) NOT NULL,
    quarter_no   TINYINT NOT NULL,
    year_no      SMALLINT NOT NULL
);
GO

IF OBJECT_ID(N'dw.dim_port', N'U') IS NULL
CREATE TABLE dw.dim_port (
    port_sk    INT IDENTITY(1, 1) PRIMARY KEY,
    port_code  NVARCHAR(10) NOT NULL UNIQUE,
    port_name  NVARCHAR(100) NOT NULL,
    country    NVARCHAR(10) NOT NULL,
    updated_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

IF OBJECT_ID(N'dw.dim_customer', N'U') IS NULL
CREATE TABLE dw.dim_customer (
    customer_sk   INT IDENTITY(1, 1) PRIMARY KEY,
    customer_id   NVARCHAR(20) NOT NULL UNIQUE,
    customer_name NVARCHAR(100) NOT NULL,
    segment       NVARCHAR(50) NOT NULL,
    updated_at    DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

IF OBJECT_ID(N'dw.dim_vessel', N'U') IS NULL
CREATE TABLE dw.dim_vessel (
    vessel_sk   INT IDENTITY(1, 1) PRIMARY KEY,
    vessel_id   NVARCHAR(20) NOT NULL UNIQUE,
    vessel_name NVARCHAR(100) NOT NULL,
    imo_no      NVARCHAR(10) NOT NULL,
    updated_at  DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);
GO

IF OBJECT_ID(N'dw.dim_tariff_tier', N'U') IS NULL
CREATE TABLE dw.dim_tariff_tier (
    tariff_tier_sk INT IDENTITY(1, 1) PRIMARY KEY,
    charge_type    NVARCHAR(10) NOT NULL,
    container_type NVARCHAR(10) NOT NULL,
    from_day       INT NOT NULL,
    to_day         INT NULL,
    rate_usd       DECIMAL(10, 2) NOT NULL,
    updated_at     DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT uq_dim_tariff_tier UNIQUE (charge_type, container_type, from_day)
);
GO

IF OBJECT_ID(N'dw.dim_container', N'U') IS NULL
CREATE TABLE dw.dim_container (
    container_sk   INT IDENTITY(1, 1) PRIMARY KEY,
    container_no   NVARCHAR(11) NOT NULL,
    container_type NVARCHAR(10) NOT NULL,
    owner_type     NVARCHAR(10) NOT NULL,
    valid_from     DATE NOT NULL,
    valid_to       DATE NULL,
    is_current     BIT NOT NULL
);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ux_dim_container_current')
CREATE UNIQUE INDEX ux_dim_container_current ON dw.dim_container (container_no) WHERE is_current = 1;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'ix_dim_container_no_valid_from')
CREATE INDEX ix_dim_container_no_valid_from ON dw.dim_container (container_no, valid_from)
    INCLUDE (valid_to, container_type, owner_type);
GO

IF NOT EXISTS (SELECT 1 FROM dw.dim_port WHERE port_sk = -1)
BEGIN
    SET IDENTITY_INSERT dw.dim_port ON;
    INSERT INTO dw.dim_port (port_sk, port_code, port_name, country) VALUES (-1, N'UNKNOWN', N'Unknown', N'XX');
    SET IDENTITY_INSERT dw.dim_port OFF;
END;
GO

IF NOT EXISTS (SELECT 1 FROM dw.dim_customer WHERE customer_sk = -1)
BEGIN
    SET IDENTITY_INSERT dw.dim_customer ON;
    INSERT INTO dw.dim_customer (customer_sk, customer_id, customer_name, segment) VALUES (-1, N'UNKNOWN', N'Unknown', N'Unknown');
    SET IDENTITY_INSERT dw.dim_customer OFF;
END;
GO

IF NOT EXISTS (SELECT 1 FROM dw.dim_vessel WHERE vessel_sk = -1)
BEGIN
    SET IDENTITY_INSERT dw.dim_vessel ON;
    INSERT INTO dw.dim_vessel (vessel_sk, vessel_id, vessel_name, imo_no) VALUES (-1, N'UNKNOWN', N'Unknown', N'0000000');
    SET IDENTITY_INSERT dw.dim_vessel OFF;
END;
GO

IF NOT EXISTS (SELECT 1 FROM dw.dim_container WHERE container_sk = -1)
BEGIN
    SET IDENTITY_INSERT dw.dim_container ON;
    INSERT INTO dw.dim_container (container_sk, container_no, container_type, owner_type, valid_from, valid_to, is_current)
    VALUES (-1, N'UNKNOWN', N'UNKNOWN', N'UNKNOWN', '1900-01-01', NULL, 1);
    SET IDENTITY_INSERT dw.dim_container OFF;
END;
GO

IF NOT EXISTS (SELECT 1 FROM dw.dim_date WHERE date_key = -1)
INSERT INTO dw.dim_date (date_key, full_date, day_of_month, day_name, is_weekend, week_of_year, month_no, month_name,
                         year_month, quarter_no, year_no)
VALUES (-1, '1900-01-01', 1, N'Unknown', 0, 1, 1, N'Unknown', '1900-01', 1, 1900);
GO

IF OBJECT_ID(N'dw.fact_container_event', N'U') IS NULL
CREATE TABLE dw.fact_container_event (
    event_id      NVARCHAR(20) NOT NULL,
    container_sk  INT NOT NULL,
    port_sk       INT NOT NULL,
    customer_sk   INT NOT NULL,
    vessel_sk     INT NOT NULL,
    date_key      INT NOT NULL,
    event_type    NVARCHAR(4) NOT NULL,
    event_ts      DATETIME2(0) NOT NULL,
    booking_ref   NVARCHAR(20) NULL,
    voyage_no     NVARCHAR(40) NULL,
    stg_loaded_at DATETIME2 NOT NULL,
    dw_loaded_at  DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT pk_fact_container_event PRIMARY KEY NONCLUSTERED (event_id),
    CONSTRAINT fk_fce_container FOREIGN KEY (container_sk) REFERENCES dw.dim_container (container_sk),
    CONSTRAINT fk_fce_port FOREIGN KEY (port_sk) REFERENCES dw.dim_port (port_sk),
    CONSTRAINT fk_fce_customer FOREIGN KEY (customer_sk) REFERENCES dw.dim_customer (customer_sk),
    CONSTRAINT fk_fce_vessel FOREIGN KEY (vessel_sk) REFERENCES dw.dim_vessel (vessel_sk),
    CONSTRAINT fk_fce_date FOREIGN KEY (date_key) REFERENCES dw.dim_date (date_key)
);
GO

IF OBJECT_ID(N'dw.fact_dd_charge', N'U') IS NULL
CREATE TABLE dw.fact_dd_charge (
    container_no  NVARCHAR(11) NOT NULL,
    cycle_no      INT NOT NULL,
    charge_type   NVARCHAR(10) NOT NULL,
    container_sk  INT NOT NULL,
    customer_sk   INT NOT NULL,
    port_sk       INT NOT NULL,
    date_key      INT NOT NULL,
    charge_days   INT NOT NULL,
    is_open       BIT NOT NULL,
    charge_usd    DECIMAL(12, 2) NOT NULL,
    as_of_date    DATE NOT NULL,
    calculated_at DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT pk_fact_dd_charge PRIMARY KEY (container_no, cycle_no, charge_type),
    CONSTRAINT fk_fdc_container FOREIGN KEY (container_sk) REFERENCES dw.dim_container (container_sk),
    CONSTRAINT fk_fdc_customer FOREIGN KEY (customer_sk) REFERENCES dw.dim_customer (customer_sk),
    CONSTRAINT fk_fdc_port FOREIGN KEY (port_sk) REFERENCES dw.dim_port (port_sk),
    CONSTRAINT fk_fdc_date FOREIGN KEY (date_key) REFERENCES dw.dim_date (date_key)
);
GO
