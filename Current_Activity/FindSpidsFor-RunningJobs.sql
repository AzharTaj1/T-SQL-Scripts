/* Script used to determine Spids for running SqlServerAgent jobs.*/
/* Script taken from: 
   -- https://social.msdn.microsoft.com/Forums/sqlserver/en-US/8af7ac39-7b09-4b84-9c1c-95573c7350d8/tsql-code-for-finding-the-spid-of-running-jobs-sql-20002005?forum=transactsql
*/

USE msdb    
GO

SET NOCOUNT ON    
SET ANSI_PADDING ON  
SET QUOTED_IDENTIFIER ON   

DECLARE @record_id int, @SQLProcessUtilization int, @CPU  int,@EventTime datetime--,@MaxCPUAllowed int    

select  top 1  @record_id =record_id, 
      @EventTime=dateadd(ms, -1 * ((SELECT ms_ticks from sys.dm_os_sys_info) - [timestamp]),  GetDate()),-- as EventTime,
      @SQLProcessUtilization=SQLProcessUtilization,
      --SystemIdle,
      --100 - SystemIdle - SQLProcessUtilization as OtherProcessUtilization,
      @CPU=SQLProcessUtilization + (100 - SystemIdle - SQLProcessUtilization) --as CPU_Usage

from (
      select 
            record.value('(./Record/@id)[1]', 'int')  as record_id,
            record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int')  as SystemIdle,
            record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int')  as SQLProcessUtilization,
            timestamp
      from (
            select timestamp, convert(xml, record) as record 
            from sys.dm_os_ring_buffers 
            where ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR'
            and record like  '%<SystemHealth>%')  as x
      ) as y 
order by record_id desc  

SELECT            
            x.session_id as [Sid],
            COALESCE(x.blocking_session_id, 0) as BSid,
            @CPU as CPU,    
            @SQLProcessUtilization as SQL,                                
            x.Status,   
            x.TotalCPU as [T.CPU],
            x.Start_time,     
            CONVERT(nvarchar(30), getdate()-x.Start_time, 108) as Elap_time,  --x.totalElapsedTime as ElapTime,
            x.totalReads as [T.RD],  -- total reads
            x.totalWrites as [T.WR],  --total writes      
            x.Writes_in_tempdb as [W.TDB],
            (
                  SELECT substring(text,x.statement_start_offset/2, 
                        (case when x.statement_end_offset = -1 
                        then len(convert(nvarchar(max), text))  * 2 
                        else x.statement_end_offset end - x.statement_start_offset+3)/2)
                  FROM sys.dm_exec_sql_text(x.sql_handle)
                  FOR XML  PATH(''), TYPE
            ) AS Sql_text,
            db_name(x.database_id) as dbName,
            (SELECT object_name(objectid) FROM sys.dm_exec_sql_text(x.sql_handle)) as object_name,            
            x.Wait_type,
            x.Login_name, 
            x.Host_name,
            CASE LEFT(x.program_name,15) 
            WHEN 'SQLAgent - TSQL' THEN  
            (     select top 1  'SQL Job = '+j.name from msdb.dbo.sysjobs (nolock) j
                  inner join msdb.dbo.sysjobsteps (nolock) s on j.job_id=s.job_id
                  where right(cast(s.job_id as nvarchar(50)),10) = RIGHT(substring(x.program_name,30,34),10) )
            WHEN 'SQL Server Prof' THEN 'SQL Server Profiler'
            ELSE x.program_name
            END as  Program_name,
            x.percent_complete,
            x.percent_complete,  
            (
                  SELECT 
                        p.text
                  FROM 
                  (
                        SELECT 
                             sql_handle,statement_start_offset,statement_end_offset
                        FROM sys.dm_exec_requests r2
                        WHERE 
                             r2.session_id = x.blocking_session_id
                  ) AS r_blocking
                  CROSS APPLY
                  (
                  SELECT substring(text,r_blocking.statement_start_offset/2, 
                        (case when r_blocking.statement_end_offset = -1 
                        then len(convert(nvarchar(max), text))  * 2 
                        else r_blocking.statement_end_offset end - r_blocking.statement_start_offset+3)/2)
                  FROM sys.dm_exec_sql_text(r_blocking.sql_handle)
                  FOR XML  PATH(''), TYPE
                  ) p (text)
            )  as blocking_text,
            (SELECT object_name(objectid) FROM sys.dm_exec_sql_text(
            (select top 1 sql_handle  FROM sys.dm_exec_requests r3 WHERE r3.session_id = x.blocking_session_id))) as blocking_obj
      FROM
      (
            SELECT 
                  r.session_id,
                  s.host_name,
                  s.login_name,
                  r.start_time,
                  r.sql_handle,
                  r.database_id,
                  r.blocking_session_id,
                  r.wait_type,
                  r.status,
                  r.statement_start_offset,
                  r.statement_end_offset, 
                  s.program_name,
                  r.percent_complete,                
                  SUM(cast(r.total_elapsed_time as bigint)) /1000 as totalElapsedTime, --CAST AS BIGINT to fix invalid data convertion when high activity
                  SUM(cast(r.reads as bigint)) AS totalReads,
                  SUM(cast(r.writes as bigint)) AS totalWrites,
                  SUM(cast(r.cpu_time as bigint)) AS totalCPU,
                  SUM(tsu.user_objects_alloc_page_count + tsu.internal_objects_alloc_page_count) AS writes_in_tempdb
            FROM sys.dm_exec_requests r
            JOIN sys.dm_exec_sessions s ON s.session_id  = r.session_id
            JOIN sys.dm_db_task_space_usage tsu ON s.session_id  = tsu.session_id  and r.request_id  = tsu.request_id
            WHERE r.status IN ('running', 'runnable',  'suspended')
            GROUP BY
                  r.session_id,
                  s.host_name,
                  s.login_name,
                  r.start_time,
                  r.sql_handle,
                  r.database_id,
                  r.blocking_session_id,
                  r.wait_type,
                  r.status,
                  r.statement_start_offset,
                  r.statement_end_offset,
                  s.program_name,
                  r.percent_complete
      ) x
      where x.session_id <> @@spid
      order by x.totalCPU desc
GO
