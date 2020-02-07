use DBMSYS
go


-- Find Snapshots on Secondaries
declare @RUN_ID int = 0,
		@SQL nvarchar(max),
		@ServerList nvarchar(max),
		@DatabaseName nvarchar(128) = 'DBAAdmin'

set @SQL =
'
SELECT hags.primary_replica, @@servername as Secondary_Replica, d.name, mf.physical_name,d.create_date
	---LEFT(physical_name,LEN(physical_name) - charindex(''\'',reverse(physical_name),1) + 1) [path]
FROM 
		sys.databases d 
inner join sys.master_files mf on mf.database_id = d.database_id
cross join 		sys.dm_hadr_availability_group_states hags  with (nolock)
	inner join sys.availability_groups ag ON ag.group_id = hags.group_id  
WHERE 
    d.source_database_id IS NOT NULL
and hags.primary_replica != @@servername
'

--Get server list - you can filter based on server name or whatever makes sense to you
set @ServerList = (
			select  distinct MOB_Name + '|1;'
			from Inventory.InstanceJobs ijb 
			inner join inventory.MonitoredObjects mob on mob.MOB_ID = ijb.IJB_MOB_ID 
			where ijb_name like 'SQLdeploy %' and mob_name not like '%prod%' ---------------and MOB_Name like 'SEASGMSSQLA0%'		--stage only--**/ and substring(mob.mob_name,4,1) ='s' and mob.mob_name not like 'gms%'
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

