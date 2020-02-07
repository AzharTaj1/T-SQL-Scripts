-- Get the last Backups History for all databases
if object_id('tempdb..#backup_history') is not null
	drop table #backup_history
create table #backup_history
(
	database_name sysname
	,physical_device_name nvarchar(260)
	,bkSize varchar(50)	
	,TimeTaken varchar(50)
	,backup_start_date datetime
	,first_lsn varchar(50)
	,last_lsn varchar(50)
	,BackupType varchar(50)
	,server_name sysname
	,recovery_model varchar(50)
)
GO

EXECUTE master.sys.sp_MSforeachdb '
USE [?];
DECLARE @DB_NAME sysname
		,@Last_Full_LSN numeric(25,0)
		,@Last_Diff_LSN numeric(25,0)

select @DB_NAME = DB_NAME()
select @Last_Full_LSN = max(last_lsn) from msdb.dbo.backupset where type = ''D'' and database_name = @DB_NAME
select @Last_Diff_LSN = max(last_lsn) from msdb.dbo.backupset where type = ''I'' and database_name = @DB_NAME and first_lsn >= @Last_Full_LSN

INSERT iNTO #backup_history
SELECT s.database_name
	,m.physical_device_name
	,CAST(CAST(s.backup_size / 1000000 AS INT) AS VARCHAR(14)) + '' '' + ''MB'' AS bkSize
	,CAST(DATEDIFF(second, s.backup_start_date, s.backup_finish_date) AS VARCHAR(4)) + '' '' + ''Seconds'' AS TimeTaken
	,s.backup_start_date
	,CAST(s.first_lsn AS VARCHAR(50)) AS first_lsn
	,CAST(s.last_lsn AS VARCHAR(50)) AS last_lsn
	,CASE s.[type]
		WHEN ''D''
			THEN ''Full''
		WHEN ''I''
			THEN ''Differential''
		WHEN ''L''
			THEN ''Transaction Log''
		END AS BackupType
	,s.server_name
	,s.recovery_model
FROM msdb.dbo.backupset s
INNER JOIN msdb.dbo.backupmediafamily m ON s.media_set_id = m.media_set_id
WHERE s.database_name = @DB_NAME -- Remove this line for all the database
AND (s.last_lsn = @Last_Full_LSN
	OR s.last_lsn = @Last_Diff_LSN
	OR s.last_lsn in (select last_lsn from msdb.dbo.backupset where type = ''L'' and database_name = @DB_NAME and first_lsn >= isnull(@Last_Diff_LSN,@Last_Full_LSN)))
'
SELECT * FROM #backup_history
ORDER BY database_name
	,backup_start_date DESC
