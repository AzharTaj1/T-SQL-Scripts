declare	@SPID int = null

select er.session_id SPID, Threads, datediff(second, start_time, getdate()) Seconds, er.Percent_Complete [%_Complete],
	cast(mg.query_cost as decimal(38, 2)) Cost, er.status, er.Wait_Type, er.Wait_Time, WaitFor_Resources,
	db_name(er.database_id) [Database], er.blocking_session_id Blocked_by,
	substring(text, case when statement_start_offset >= datalength(text)
       then 1
       else (statement_start_offset/2)+1
      end,
      case when statement_end_offset < 1
       then datalength(text)
       else statement_end_offset end
      - case when statement_start_offset >= datalength(text)
       then 1
       else (statement_start_offset/2)+1
      end + 1) [Statement],
	object_schema_name(st.objectid, er.database_id) + '.' + object_name(st.objectid, er.database_id) [Object], cast(p.Query_Plan as xml) [Plan],
	er.Cpu_Time, er.Logical_Reads, er.scheduler_id, es.[Host_Name] Host, es.Login_Name [Login], es.[Program_Name] Program,
	mg.granted_memory_kb/1024 Granted_Memory_MB, Scheduler_Pending_IO_Tasks, Scheduler_Pending_IO_ms
from sys.dm_exec_requests er 
	inner join sys.dm_os_schedulers sc on er.scheduler_id = sc.scheduler_id
	outer apply sys.dm_exec_sql_text(er.sql_handle) st 
	outer apply sys.dm_exec_text_query_plan(er.plan_handle, er.statement_start_offset, er.statement_end_offset) p 
	left join sys.dm_exec_sessions es ON es.session_id = er.session_id 
	left join sys.dm_exec_query_memory_grants mg on mg.session_id = er.session_id 
	cross apply (select count(*) Threads from master..sysprocesses where spid = er.session_id) sp 
	outer apply (select STUFF((select ',(' + wt.resource_description + ')'
							from sys.dm_os_waiting_tasks wt
							where wt.session_id = er.session_id
								and wt.resource_description not like 'exchangeEvent id=%'
								and wt.resource_description not like 'ACCESS_METHODS_DATASET_PARENT%'
							for xml path('')), 1, 1,'') WaitFor_Resources) wt
	outer apply (select COUNT(*) Scheduler_Pending_IO_Tasks, SUM(pir.io_pending_ms_ticks) Scheduler_Pending_IO_ms
				from sys.dm_io_pending_io_requests pir
				where pir.scheduler_address = sc.scheduler_address) pir
where er.session_id <> @@spid
	and es.[status] = 'Running'
	and (er.session_id = @SPID or @SPID is null)
order by case when er.wait_type = 'WAITFOR' then 1 else 0 end, Threads desc, Seconds desc, SPID

select DB_NAME(dt.database_id) DB, st.session_id, dt.database_transaction_begin_time,
	DATEDIFF(minute, dt.database_transaction_begin_time, getdate()) [Minutes] 
from sys.dm_tran_session_transactions st
	inner join sys.dm_tran_database_transactions dt on st.transaction_id = dt.transaction_id
where dt.database_id <> 32767 and database_transaction_begin_time is not null
	and (st.session_id = @SPID or @SPID is null)
order by database_transaction_begin_time