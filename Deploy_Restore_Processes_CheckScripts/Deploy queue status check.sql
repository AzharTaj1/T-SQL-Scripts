-- Check for errors on SQL Deploy queues
use dbmsys
go



declare @RUN_ID int = 0,
		@SQL nvarchar(max),
		@ServerList nvarchar(max),
		@DatabaseName nvarchar(128) = 'SQLDeploy'

-- Check deploy queues across all NON-Production servers
set @SQL =
'
	select 
		@@servername as [In-Progress Server]
		, datediff(minute, rl.startdate, getDate()) as ElapsedMinutes
		, (select avg(datediff(minute, rl2.startdate, isNull(rl2.ModDate,getDate())) )  from sqldeploy.dbo.Request_local rl2 with (nolock) where rl2.Process = rl.Process and rl2.dbname =rl.dbname ) as AverageMinutes
		, rl.* 
	from 
		sqldeploy.dbo.Request_local rl with (nolock)
	-- where status like ''in-work%ERROR''	--Only Error check-- 
	where status like ''in-work%'' or status  = ''pending''  --General activity check--
	order by ahrequestid desc	 
'

--Get server list - you can filter based on server name or whatever makes sense to you
set @ServerList = (
			select  distinct MOB_Name + '|1;'
			from Inventory.InstanceJobs ijb 
			inner join inventory.MonitoredObjects mob on mob.MOB_ID = ijb.IJB_MOB_ID 
			where ijb_name like 'SQLdeploy %' and mob_name not like '%Prod%' 
			for xml path('')
				)

-- Recent SQLDeploy failures 
SELECT mob_name as [Failed Server], flj.*
FROM [DBMSYS].[Activity].[FailedJobs] flj
inner join [DBMSYS].inventory.MonitoredObjects mob on mob_id = FLJ_MOB_ID
where  FLJ_JobName  like 'SQLDeploy %'  and FLJ_LastFailureDate > getDate() -1
order by flj_lastfailuredate desc


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
