use DBMSYS
go

-- Find Snapshot Orphans
declare @RUN_ID int = 0,
		@SQL nvarchar(max),
		@ServerList nvarchar(max),
		@DatabaseName nvarchar(128) = 'DBAAdmin'

set @SQL =
'
--
--find known snapshots
--
declare @folders table (FolderName	varchar(1000))
declare @snaps table (FolderName	varchar(1000), FileName		varchar(1000))
declare @files table (FolderName	varchar(1000), FileName		varchar(1000))
declare @batchCmd	varchar(1000)


--Identify snap directory(s)
insert into @folders(FolderName)
SELECT distinct
	LEFT(physical_name,LEN(physical_name) - charindex(''\'',reverse(physical_name),1) + 1) [path]
FROM 
		sys.databases d 
inner join sys.master_files mf on mf.database_id = d.database_id
WHERE 
    source_database_id IS NOT NULL

if not exists (select * from @folders)
begin
---	insert into @folders values (''e:\nxt'')
	insert into @folders select ''\\'' + @@servername + ''\'' + @@servername + ''_nxt''
end
--select * from @folders


declare @tmpFiles table (FileName		varchar(1000))
declare @rowFolder_COLUMN_NAME		varchar(1000)

declare rsFolder cursor local fast_forward read_only for select FolderName from @folders
open rsFolder ;
fetch from rsFolder
into
    @rowFolder_COLUMN_NAME
while (@@fetch_status <> -1) --FETCH statement failed or the row was beyond the result set.
begin
    if (@@fetch_status <> -2) --Row fetched is missing.
    begin

	set @batchCmd = ''dir '' + @rowFolder_COLUMN_NAME + ''/b''
	insert into @tmpFiles 
	execute xp_cmdshell @batchCmd
	insert into @files (FolderName,FileName) select @rowFolder_COLUMN_NAME, Filename from @tmpFiles where FileName is not null

    end
    fetch next from rsFolder
    into
        @rowFolder_COLUMN_NAME
end
close rsFolder ;
deallocate rsFolder


---select * from @files


insert into @snaps (FolderName, FileName)
 SELECT 
		LEFT(physical_name,LEN(physical_name) - charindex(''\'',reverse(physical_name),1) + 1) [path]
		,dbaadmin.dbo.dbaudf_GetFileProperty(mf.physical_name,''File'',''Name'') filename
    FROM 
		  sys.databases d 
	inner join sys.master_files mf on mf.database_id = d.database_id
    WHERE 
        source_database_id IS NOT NULL

		
select 
	@@servername, * 
from 
	@files f 
left outer join @snaps s on s.FolderName = f.FolderName and s.filename = f.filename
where 
	s.filename is null
'

--Get server list - you can filter based on server name or whatever makes sense to you
set @ServerList = (
			select  distinct MOB_Name + '|1;'
			from Inventory.InstanceJobs ijb 
			inner join inventory.MonitoredObjects mob on mob.MOB_ID = ijb.IJB_MOB_ID 
			where ijb_name like 'SQLdeploy %' and mob_name not like '%prod%' 		--stage only--**/ and substring(mob.mob_name,4,1) ='s' and mob.mob_name not like 'gms%'
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

