use DBMSYS
go

-- Recent BASELINE failures 
SELECT mob_name as [Failed on Server], flj.*
FROM [DBMSYS].[Activity].[FailedJobs] flj
inner join [DBMSYS].inventory.MonitoredObjects mob on mob_id = FLJ_MOB_ID
where  FLJ_JobName  like 'BASE %'  and FLJ_LastFailureDate > getDate() -2
order by flj_lastfailuredate desc
go


-------------------------------------------------------------------
-- Check activity on BASE queue
-- (row indicates baseline in-progress, absense of row indicates process complete.)

declare @RUN_ID int = 0,
		@SQL nvarchar(max),
		@ServerList nvarchar(max),
		@DatabaseName nvarchar(128) = 'DBAAdmin'

set @SQL =
'
select @@servername as [Running on Server],* from DBAAdmin.dbo.Local_Control where subject = ''job_control_BASE''
'

--Get server list - you can filter based on server name or whatever makes sense to you
set @ServerList = (
			select  distinct MOB_Name + '|1;'
			from Inventory.InstanceJobs ijb 
			inner join inventory.MonitoredObjects mob on mob.MOB_ID = ijb.IJB_MOB_ID 
			where ijb_name like 'BASE 00 - Controller' and mob_name not like '%prod%' 
			for xml path('')
				)
--Execution
exec SYL.usp_RunCommand
@QueryType = 1
, @ServerList = @ServerList
, @Command = @SQL
, @Database = @DatabaseName
, @RUN_ID = @RUN_ID output

--See execution results
select *
from SYL.ServerRunResult
where SRR_RUN_ID = @RUN_ID
go

