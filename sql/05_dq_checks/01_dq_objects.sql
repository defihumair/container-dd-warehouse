USE dd_warehouse;
GO

IF OBJECT_ID(N'dq.check_result', N'U') IS NULL
CREATE TABLE dq.check_result (
    check_id    INT IDENTITY PRIMARY KEY,
    dq_run_id   INT NOT NULL,
    run_ts      DATETIME2 NOT NULL,
    check_name  NVARCHAR(100) NOT NULL,
    severity    NVARCHAR(10) NOT NULL,
    failed_rows INT NOT NULL,
    threshold   INT NOT NULL,
    status      NVARCHAR(10) NOT NULL
);
GO

IF OBJECT_ID(N'dq.quarantine_cycle', N'U') IS NULL
CREATE TABLE dq.quarantine_cycle (
    container_no NVARCHAR(11) NOT NULL,
    booking_ref  NVARCHAR(20) NOT NULL,
    issue        NVARCHAR(50) NOT NULL,
    disc_ts      DATETIME2(0) NULL,
    gtot_ts      DATETIME2(0) NULL,
    gtin_ts      DATETIME2(0) NULL,
    detected_at  DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT pk_quarantine_cycle PRIMARY KEY (container_no, booking_ref)
);
GO

CREATE OR ALTER FUNCTION dq.fn_iso6346_check_digit (@code10 NVARCHAR(10))
RETURNS INT
AS
BEGIN
    DECLARE @i INT = 1, @total INT = 0, @ch NCHAR(1), @n INT, @val INT;

    IF @code10 IS NULL OR LEN(@code10) <> 10
        RETURN NULL;

    WHILE @i <= 10
    BEGIN
        SET @ch = UPPER(SUBSTRING(@code10, @i, 1));
        IF @ch LIKE N'[0-9]'
            SET @val = UNICODE(@ch) - 48;
        ELSE IF @ch LIKE N'[A-Z]'
        BEGIN
            SET @n = UNICODE(@ch) - 65;
            SET @val = 10 + @n + CASE WHEN @n >= 21 THEN 3 WHEN @n >= 11 THEN 2 WHEN @n >= 1 THEN 1 ELSE 0 END;
        END
        ELSE
            RETURN NULL;

        SET @total += @val * POWER(2, @i - 1);
        SET @i += 1;
    END;

    RETURN @total % 11 % 10;
END;
GO

CREATE OR ALTER FUNCTION dq.fn_is_valid_container_no (@container_no NVARCHAR(20))
RETURNS BIT
AS
BEGIN
    IF @container_no IS NULL
       OR @container_no NOT LIKE N'[A-Z][A-Z][A-Z][UJZ][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'
        RETURN 0;

    RETURN CASE
               WHEN UNICODE(RIGHT(@container_no, 1)) - 48 = dq.fn_iso6346_check_digit(LEFT(@container_no, 10))
               THEN 1 ELSE 0
           END;
END;
GO

SELECT N'CSQU3054383' AS container_no, dq.fn_is_valid_container_no(N'CSQU3054383') AS is_valid, 1 AS expected
UNION ALL
SELECT N'CSQU3054384', dq.fn_is_valid_container_no(N'CSQU3054384'), 0;
GO
