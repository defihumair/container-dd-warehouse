USE msdb;
GO

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'dd_daily_transform')
    EXEC msdb.dbo.sp_delete_job @job_name = N'dd_daily_transform';
GO

EXEC msdb.dbo.sp_add_job
     @job_name    = N'dd_daily_transform',
     @description = N'Runs etl.run_transform: staging, dimensions, fact, data quality, D&D charges.';

EXEC msdb.dbo.sp_add_jobstep
     @job_name       = N'dd_daily_transform',
     @step_name      = N'run transform',
     @subsystem      = N'TSQL',
     @database_name  = N'dd_warehouse',
     @command        = N'EXEC etl.run_transform;',
     @retry_attempts = 1,
     @retry_interval = 5;

IF NOT EXISTS (SELECT 1 FROM msdb.dbo.sysschedules WHERE name = N'daily_0200')
    EXEC msdb.dbo.sp_add_schedule
         @schedule_name     = N'daily_0200',
         @freq_type         = 4,
         @freq_interval     = 1,
         @active_start_time = 020000;

EXEC msdb.dbo.sp_attach_schedule @job_name = N'dd_daily_transform', @schedule_name = N'daily_0200';
EXEC msdb.dbo.sp_add_jobserver @job_name = N'dd_daily_transform', @server_name = N'(local)';
GO

EXEC msdb.dbo.sp_start_job @job_name = N'dd_daily_transform';
GO

DECLARE @tries INT = 0, @running BIT = 1;
WAITFOR DELAY '00:00:05';
WHILE @running = 1 AND @tries < 60
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM msdb.dbo.sysjobactivity AS a
        JOIN msdb.dbo.sysjobs AS j ON j.job_id = a.job_id
        WHERE j.name = N'dd_daily_transform'
          AND a.session_id = (SELECT MAX(session_id) FROM msdb.dbo.syssessions)
          AND a.start_execution_date IS NOT NULL
          AND a.stop_execution_date IS NULL
    )
        SET @running = 0;
    ELSE
    BEGIN
        WAITFOR DELAY '00:00:05';
        SET @tries += 1;
    END;
END;
GO

SELECT TOP (4) j.name AS job_name, h.step_id, h.step_name,
       CASE h.run_status WHEN 1 THEN 'succeeded' WHEN 0 THEN 'failed' WHEN 2 THEN 'retry' ELSE 'other' END AS result,
       msdb.dbo.agent_datetime(h.run_date, h.run_time) AS run_at,
       h.run_duration AS duration_hhmmss,
       LEFT(h.message, 200) AS message
FROM msdb.dbo.sysjobhistory AS h
JOIN msdb.dbo.sysjobs AS j ON j.job_id = h.job_id
WHERE j.name = N'dd_daily_transform'
ORDER BY h.instance_id DESC;

SELECT s.name AS schedule_name, s.enabled,
       STUFF(STUFF(RIGHT('000000' + CAST(s.active_start_time AS VARCHAR(6)), 6), 5, 0, ':'), 3, 0, ':') AS runs_daily_at
FROM msdb.dbo.sysschedules AS s
JOIN msdb.dbo.sysjobschedules AS js ON js.schedule_id = s.schedule_id
JOIN msdb.dbo.sysjobs AS j ON j.job_id = js.job_id
WHERE j.name = N'dd_daily_transform';
GO
