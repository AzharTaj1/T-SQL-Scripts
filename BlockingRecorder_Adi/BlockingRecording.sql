use DBAPerf

if object_id('dbo.BlockedSessions') is null
	create table dbo.BlockedSessions
		(ID int not null identity,
		RecordedDateTime datetime not null,
		SessionID smallint not null,
		HostName nvarchar(128) null,
		SessionStatus nvarchar(30) null,
		DatabaseName nvarchar(128) null,
		BlockerSessionID smallint null,
		SQLStatement nvarchar(max) null,
		WaitForResources nvarchar(max) null,
		CPUTime int null,
		Reads bigint null,
		Writes bigint null,
		WaitTime int null,
		WaitType nvarchar(60) null,
		StartTime datetime null,
		ProgramName nvarchar(128) null,
		ObjectID int null,
		ThreadCount int null,
		LoginName nvarchar(128) null,
		HasARunningRequest bit null)
GO
if not exists (select * from sys.indexes where name = 'IX_BlockedSessions_RecordedDateTime#ID')
	create unique clustered index IX_BlockedSessions_RecordedDateTime#ID on dbo.BlockedSessions(RecordedDateTime, ID)
GO
if object_id('dbo.usp_PurgeBlockedSessions') is not null
	drop procedure dbo.usp_PurgeBlockedSessions
GO
create procedure dbo.usp_PurgeBlockedSessions
as
declare @ChunkSize int,
		@FirstDate datetime

set nocount on

select @ChunkSize = 1000,
	 @FirstDate = getdate() - 30
while @@ROWCOUNT > 0
	delete top(@ChunkSize)
	from dbo.BlockedSessions
	where RecordedDateTime <= @FirstDate
GO
if object_id('dbo.usp_RecordBlockedSessions') is not null
	drop procedure dbo.usp_RecordBlockedSessions
GO
create procedure dbo.usp_RecordBlockedSessions
as
insert into dbo.BlockedSessions
select getdate() DT, r.session_id, s.[host_name], s.[status],
	db_name(r.database_id) DatabaseName, r.blocking_session_id BlockerSessionID,
	left(substring(t.[text], (r.statement_start_offset/2) + 1, ((case r.statement_end_offset
																		when -1 then datalength(t.[text])
																		when 0 then datalength(t.[text])
																		else r.statement_end_offset
																	end - r.statement_start_offset)/2) + 1), 8000) SQLStatement,
	wt.WaitForResources, r.cpu_time, r.reads, r.writes, r.wait_time, r.wait_type, r.start_time,
	[program_name], t.objectid, sp.ThreadCount,
	s.login_name, 1 HasARunningRequest
from sys.dm_exec_requests r
	inner join sys.dm_exec_sessions s on s.session_id = r.session_id
	cross APPLY sys.dm_exec_sql_text (r.sql_handle) t
	cross apply (select count(*) ThreadCount
					from sys.sysprocesses
					where spid = r.session_id) sp
	outer apply (select stuff((select ',(' + wt.resource_description + ')'
							from sys.dm_os_waiting_tasks wt
							where wt.session_id = r.session_id
								and wt.resource_description not like 'exchangeEvent id=%'
								and wt.resource_description not like 'ACCESS_METHODS_DATASET_PARENT%'
							for xml path('')), 1, 1,'') WaitForResources) wt
where blocking_session_id > 0
	or r.session_id in (select blocking_session_id
						from sys.dm_exec_requests
						where blocking_session_id > 0)
union all
select getdate() DT, st.session_id, s.[host_name], s.[status], db_name(dt.database_id) DatabaseName, null BlockerSessionID, null SQLStatement, null WaitForResources,
	s.cpu_time, s.reads, s.writes, null wait_time, null wait_type, dt.database_transaction_begin_time start_time, s.[program_name], null objectid, 1 ThreadCount,
	s.login_name, 0 HasARunningRequest
from sys.dm_tran_session_transactions st
	inner join sys.dm_tran_database_transactions dt on st.transaction_id = dt.transaction_id
	inner join sys.dm_exec_sessions s on s.session_id = st.session_id
where dt.database_id <> 32767
	and database_transaction_begin_time is not null
	and not exists (select *
						from sys.dm_exec_requests r
						where r.session_id = st.session_id)
GO
if object_id('fn_BlockResourceExtraction') is not null
	drop function fn_BlockResourceExtraction
GO
create function fn_BlockResourceExtraction(@ResourceString nvarchar(max),
											@Key nvarchar(100)) returns table
as
return
	(with Level1 as
			(select charindex(@Key, @ResourceString, 1) KeyStart
			)
		, Level2 as
			(select substring(@ResourceString, KeyStart, charindex(' ', @ResourceString, KeyStart) - KeyStart) KeyAndValue
				from Level1
			)
	select substring(KeyAndValue, charindex('=', KeyAndValue, 1) + 1, len(@ResourceString)) Value
	from Level2)
GO
if object_id('usp_BlockingReport') is not null
	drop procedure usp_BlockingReport
GO
create procedure usp_BlockingReport
	@FromDate datetime = null,
	@ToDate datetime = null
as
set nocount on
if object_id('tempdb..#Blocks') is not null
	drop table #Blocks
if object_id('tempdb..#BlockedResources') is not null
	drop table #BlockedResources

if @FromDate is null
	set @FromDate = 0

if @ToDate is null
	set @ToDate = getdate()

;with Blockings as
	(select RecordedDateTime, SessionID, DatabaseName, object_schema_name(ObjectID, db_id(DatabaseName)) + '.' + object_name(ObjectID, db_id(DatabaseName)) BlockerObjectName,
				SQLStatement BlockerStatement, cast(null as nvarchar(257)) BlockedObjectName, cast(null as nvarchar(max)) BlockedStatement,
				cast(null as int) WaitTime, cast(null as nvarchar(max)) WaitForResources
		from BlockedSessions
		where BlockerSessionID = 0
			and RecordedDateTime between @FromDate and @ToDate
		union all
		select a.RecordedDateTime, b.SessionID, a.DatabaseName, a.BlockerObjectName, a.BlockerStatement, 
			object_schema_name(b.ObjectID, db_id(b.DatabaseName)) + '.' + object_name(b.ObjectID, db_id(b.DatabaseName)) BlockedObjectName, b.SQLStatement BlockedStatement,
			b.WaitTime, b.WaitForResources
		from Blockings a
			inner join BlockedSessions b on a.RecordedDateTime = b.RecordedDateTime
											and a.SessionID = b.BlockerSessionID 
		)
select row_number() over(order by count(*) desc) ID, DatabaseName, BlockerObjectName, BlockerStatement, BlockedObjectName, BlockedStatement, b.WaitForResources, count(*) Blocks, sum(WaitTime) WaitTime
into #Blocks
from Blockings a
	cross apply (select top 1 WaitForResources
					from Blockings b
					where b.BlockerStatement = a.BlockerStatement
						and b.BlockedStatement = a.BlockedStatement) b
where WaitTime is not null
	and b.WaitForResources is not null
group by DatabaseName, BlockerObjectName, BlockerStatement, BlockedObjectName, BlockedStatement, b.WaitForResources
order by Blocks desc

select ID, r.*
into #BlockedResources
from #Blocks
	outer apply (select coalesce(a.DatabaseID, b.DatabaseID, c.DatabaseID, d.DatabaseID) DatabaseID, ObjectID, PartitionID, coalesce(c.FileID, d.FileID) FileID,
							coalesce(c.PageID, d.PageID) PageID, SubResourceName
					from (select 1 a) t
							outer apply
								(select d.Value DatabaseID, p.Value PartitionID
									from fn_BlockResourceExtraction(WaitForResources, 'dbid') d
										cross apply fn_BlockResourceExtraction(WaitForResources, 'hobtid') p
									where WaitForResources like '%hobtid=%dbid=%'
								) a
							outer apply
								(select d.Value DatabaseID, o.Value ObjectID
									from fn_BlockResourceExtraction(WaitForResources, 'dbid') d
										cross apply fn_BlockResourceExtraction(WaitForResources, 'objid') o
									where WaitForResources like '%objid=%dbid=%'
								) b
							outer apply
								(select cast(parsename(PagePointer, 3) as int) DatabaseID, cast(parsename(PagePointer, 2) as int) FileID, cast(parsename(PagePointer, 1) as int) PageID
									from (select replace(replace(replace('(12:6:56811984)', '(', ''), ')', ''), ':', '.') PagePointer) t
									where WaitForResources like '%:%:%'
								) c
							outer apply
								(select d.Value DatabaseID, f.Value FileID, p.Value PageID
									from fn_BlockResourceExtraction(WaitForResources, 'dbid') d
										cross apply fn_BlockResourceExtraction(WaitForResources, 'fileid') f
										cross apply fn_BlockResourceExtraction(WaitForResources, 'pageid') p
									where WaitForResources like '%fileid=%pageid=%dbid=%'
								) d
							outer apply
								(select s.Value SubResourceName
									from fn_BlockResourceExtraction(WaitForResources, 'subresource') s
									where WaitForResources like '%metadatalock subresource=%'
								) e
					) r

if object_id('tempdb..#PageResults') is not null
	drop table #PageResults
create table #PageResults(ParentObject nvarchar(max),
								Objct nvarchar(max),
								Field nvarchar(max),
								Value nvarchar(max))

declare @DatabaseID varchar(100),
	@FileID varchar(100),
	@PageID varchar(100),
	@PartitionID varchar(100),
	@ObjectID int,
	@SQL nvarchar(max)

declare cPages cursor static forward_only for
	select distinct DatabaseID, FileID, PageID
	from #BlockedResources
	where PageID is not null
		and DatabaseID <> 2
		and ObjectID is null

open cPages

fetch next from cPages into @DatabaseID, @FileID, @PageID
while @@FETCH_STATUS = 0
begin
	set @SQL = concat('dbcc page(', @DatabaseID, ', ', @FileID, ', ', @PageID, ', 0) WITH TABLERESULTS;')

	truncate table #PageResults
	set @ObjectID = null

	begin try
		insert into #PageResults
		exec(@SQL)

		select @ObjectID = Value
		from #PageResults
		where Field = 'Metadata: ObjectId'
			and Value <> '0'

		if @@rowcount > 0
		update #BlockedResources
		set ObjectID = @ObjectID
		where DatabaseID = @DatabaseID
			and FileID = @FileID
			and PageID = @PageID
	end try
	begin catch
	end catch
	fetch next from cPages into @DatabaseID, @FileID, @PageID
end
close cPages
deallocate cPages

declare cPartitionIDs cursor static forward_only for
	select distinct DatabaseID, PartitionID
	from #BlockedResources
	where PartitionID is not null
		and DatabaseID <> 2
		and ObjectID is null

open cPartitionIDs

fetch next from cPartitionIDs into @DatabaseID, @PartitionID
while @@FETCH_STATUS = 0
begin
	set @SQL = 'use ' + quotename(db_name(@DatabaseID)) + ' select @ObjectID = object_id from sys.partitions where [partition_id] = ' + @PartitionID

	exec sp_executesql @SQL,
					N'@ObjectID int output',
					@ObjectID = @ObjectID output

	update #BlockedResources
	set ObjectID = @ObjectID
	where DatabaseID = @DatabaseID
		and PartitionID = @PartitionID
		and @PartitionID is not null

	fetch next from cPartitionIDs into @DatabaseID, @PartitionID
end
close cPartitionIDs
deallocate cPartitionIDs

select b.DatabaseName, coalesce(object_schema_name(r.ObjectID, db_id(b.DatabaseName)) + '.' + object_name(r.ObjectID, db_id(b.DatabaseName)), quotename(SubResourceName),
											iif(r.DatabaseID = 2, '[tempdb object]', null), '[N/A]') BlockedResource,
	isnull(b.BlockerObjectName, '') BlockerObjectName, '"' + replace(BlockerStatement, '"', '""') + '"' BlockerStatement,
	isnull(BlockedObjectName, '') BlockedObjectName, '"' + replace(BlockedStatement, '"', '""') + '"' BlockedStatement, Blocks, WaitTime
from #Blocks b
	inner join #BlockedResources r on b.ID = r.ID
GO
if exists (select * from msdb.dbo.sysjobs where name = 'UTIL - DBA Purge Old Records')
	return

BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
	EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
	IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'UTIL - DBA Purge Old Records', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'No description available.', 
		@category_name=N'[Uncategorized (Local)]', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'DBAJob', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'exec dbo.usp_PurgeBlockedSessions', 
		@database_name=N'DBAPerf', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Daily_at_0112', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=1, 
		@freq_subday_interval=0, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20170206, 
		@active_end_date=99991231, 
		@active_start_time=11200, 
		@active_end_time=235959
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO
if exists (select * from msdb.dbo.sysjobs where name = 'UTIL - DBA Record Blocked Sessions')
	return
BEGIN TRANSACTION
DECLARE @ReturnCode INT
SELECT @ReturnCode = 0
IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name=N'[Uncategorized (Local)]' AND category_class=1)
BEGIN
	EXEC @ReturnCode = msdb.dbo.sp_add_category @class=N'JOB', @type=N'LOCAL', @name=N'[Uncategorized (Local)]'
	IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
END

DECLARE @jobId BINARY(16)
EXEC @ReturnCode =  msdb.dbo.sp_add_job @job_name=N'UTIL - DBA Record Blocked Sessions', 
		@enabled=1, 
		@notify_level_eventlog=0, 
		@notify_level_email=0, 
		@notify_level_netsend=0, 
		@notify_level_page=0, 
		@delete_level=0, 
		@description=N'No description available.', 
		@category_name=N'[Uncategorized (Local)]', 
		@owner_login_name=N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id=@jobId, @step_name=N'Run', 
		@step_id=1, 
		@cmdexec_success_code=0, 
		@on_success_action=1, 
		@on_success_step_id=0, 
		@on_fail_action=2, 
		@on_fail_step_id=0, 
		@retry_attempts=0, 
		@retry_interval=0, 
		@os_run_priority=0, @subsystem=N'TSQL', 
		@command=N'exec dbo.usp_RecordBlockedSessions', 
		@database_name=N'DBAPerf', 
		@flags=0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id=@jobId, @name=N'Every_1_minute', 
		@enabled=1, 
		@freq_type=4, 
		@freq_interval=1, 
		@freq_subday_type=4, 
		@freq_subday_interval=1, 
		@freq_relative_interval=0, 
		@freq_recurrence_factor=0, 
		@active_start_date=20170206, 
		@active_end_date=99991231, 
		@active_start_time=0, 
		@active_end_time=235959
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO
