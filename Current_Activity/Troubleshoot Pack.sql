--Deadlocks
set transaction isolation level read uncommitted
set nocount on
declare @x xml
select @x = CAST(target_data as xml)
from sys.dm_xe_session_targets t
	inner join sys.dm_xe_sessions s on t.event_session_address = s.address
where s.name = 'system_health'

;with Deadlocks as
		(select CAST(event_data as xml) event_data
			from sys.fn_xe_file_target_read_file(@x.value('(EventFileTarget/File/@name)[1]', 'varchar(1000)'), null, null, null)
			where [object_name] = 'xml_deadlock_report'
		)
select event_data.value('(event/@timestamp)[1]', 'datetime') EventDate,
	b.query('.') DeadLockGraph,
	dateadd(hour, -DATEDIFF(hour, getdate(), getutcdate()), event_data.value('(event/@timestamp)[1]', 'datetime')) ServerDate
from Deadlocks
	outer apply event_data.nodes('event/data/value/deadlock') a(b)

--What's running
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
GO
--Waits

/*
dbcc sqlperf('sys.dm_os_wait_stats', clear)
*/
select *
from sys.dm_os_wait_stats
order by 3 desc
GO
--Cache

set transaction isolation level read uncommitted
set nocount on
declare @Top int,
		@MinServerOnlineHours int,
		@DatabaseName nvarchar(128)
select @Top = 10,
	@DatabaseName = 'CreditPack'

;with ByCPU as
		(select top(@Top) DatabaseName, [sql_handle], plan_handle, statement_start_offset, statement_end_offset,
						execution_count TotalExecutions, total_logical_reads TotalReads,
						total_worker_time TotalCPU, total_elapsed_time/1000000 TotalDurationSec,
						total_logical_reads/execution_count AverageReads,
						total_worker_time/execution_count AverageCPU,
						total_elapsed_time/1000000/execution_count AverageDurationSec
			from sys.dm_exec_query_stats
				cross apply (select db_name(cast(value as int)) DatabaseName
								from sys.dm_exec_plan_attributes(plan_handle)
								where attribute = 'dbid') a
			where DatabaseName = @DatabaseName
				or @DatabaseName is null
			order by total_worker_time desc)
	, ByReads as
		(select top(@Top) DatabaseName, [sql_handle], plan_handle, statement_start_offset, statement_end_offset,
						execution_count TotalExecutions, total_logical_reads TotalReads,
						total_worker_time TotalCPU, total_elapsed_time/1000000 TotalDurationSec,
						total_logical_reads/execution_count AverageReads,
						total_worker_time/execution_count AverageCPU,
						total_elapsed_time/1000000/execution_count AverageDurationSec
			from sys.dm_exec_query_stats
				cross apply (select db_name(cast(value as int)) DatabaseName
								from sys.dm_exec_plan_attributes(plan_handle)
								where attribute = 'dbid') a
			where DatabaseName = @DatabaseName
				or @DatabaseName is null
			order by total_logical_reads desc)
	, AllQueries as
		(select *
			from ByCPU
			union
			select *
			from ByReads)
select top(@Top) DatabaseName,
				object_name(isnull(ps.object_id, ts.object_id), isnull(ps.database_id, ts.database_id)) ObjectName,
				substring(text, (statement_start_offset/2)+1,
				((case statement_end_offset
						when -1 then datalength(text)
						when 0 then datalength(text)
						else statement_end_offset
					end - statement_start_offset)/2) + 1) [Statement], p.query_plan QueryPlan,
				TotalExecutions, TotalReads, TotalCPU, TotalDurationSec,
				AverageReads, AverageCPU, AverageDurationSec
from AllQueries a
		cross apply sys.dm_exec_sql_text(sql_handle) t
		cross apply sys.dm_exec_query_plan(plan_handle) p
		left join sys.dm_exec_procedure_stats ps on a.plan_handle = ps.plan_handle
		left join sys.dm_exec_trigger_stats ts on a.plan_handle = ts.plan_handle
GO
--Index usage
select db_name(database_id) [Database],
	t.name [Table],
	si.name [Index],
	s.*
	, 'DROP INDEX ' + quotename(si.name) + ' ON ' + quotename(t.name) DropScript,
	N'CREATE ' + case when si.is_unique = 1 then N'UNIQUE ' else N'' end
            + case when si.type = 1 then 'CLUSTERED'
                                          else 'NONCLUSTERED' end + N' INDEX ' + quotename(si.name)
                              + N' ON ' + quotename(schema_name(t.schema_id)) + '.' + quotename(t.name) + '(' +
      stuff((select ',' + quotename(c.name) + ' ' + case when is_descending_key = 1 then N'DESC' else N'ASC' end
            from sys.columns c with (nolock)
                        inner join sys.index_columns ic with (nolock) on c.object_id = ic.object_id
                                                                        and c.column_id = ic.column_id
            where is_included_column = 0 and ic.index_id = si.index_id and ic.object_id = si.object_id and key_ordinal <> 0
            order by key_ordinal
            for xml path('')), 1, 1, '') + ')' +
      isnull(' INCLUDE(' + stuff((select ',' + quotename(c.name)
            from sys.columns c with (nolock)
                        inner join sys.index_columns ic with (nolock) on c.object_id = ic.object_id
                                                                        and c.column_id = ic.column_id
            where is_included_column = 1 and ic.index_id = si.index_id and ic.object_id = si.object_id
            order by key_ordinal
            for xml path('')), 1, 1, '') + ')', '')
            CreateScript
from sys.dm_db_index_usage_stats s
	inner join sys.indexes si on si.object_id = s.object_id and si.index_id = s.index_id
	inner join sys.tables t on t.object_id = s.object_id
where database_id = db_id('CreditPack')
	and si.index_id > 0
	and si.is_primary_key = 0
order by user_seeks + user_lookups