/* Provides information regarding database backups which have been happening on the SQL server. Script provided by Vladyslav Ivanov. */

;with BackupHistory as (
SELECT 
CONVERT(CHAR(100), SERVERPROPERTY('Servername')) AS Server, 
msdb.dbo.backupset.database_name, 
msdb.dbo.backupset.backup_start_date, 
msdb.dbo.backupset.backup_finish_date, 
DATEDIFF (SECOND, msdb.dbo.backupset.backup_start_date, msdb.dbo.backupset.backup_finish_date) Elapsed_Time_sec,
msdb.dbo.backupset.expiration_date, 
CASE msdb..backupset.type 
WHEN 'D' THEN 'Database' 
WHEN 'L' THEN 'Log' 
WHEN 'I' THEN 'Differential' 
END AS backup_type, 
msdb.dbo.backupset.backup_size /1024./1024. as backup_size_mb, 
(msdb.dbo.backupset.compressed_backup_size/1024./1024.) AS compressed_size_mb,
CONVERT (NUMERIC (20,3), (CONVERT (FLOAT, msdb.dbo.backupset.backup_size) /CONVERT (FLOAT, msdb.dbo.backupset.compressed_backup_size))) Compression_Ratio,
--(msdb.dbo.backupset.compressed_backup_size - lag(msdb.dbo.backupset.compressed_backup_size, 1) over (partition by database_name order by backup_start_date)) /1024./1024. as backup_growth_mb,
msdb.dbo.backupset.is_copy_only,
msdb.dbo.backupmediafamily.logical_device_name, 
msdb.dbo.backupmediafamily.physical_device_name, 
msdb.dbo.backupset.name AS backupset_name, 
msdb.dbo.backupset.description,
ROW_NUMBER() over (partition by backupset.database_name, backupset.backup_start_date order by backupmediafamily.physical_device_name) as FileNo,
count(database_name) over (partition by backupset.database_name, backupset.backup_start_date) as Files
FROM msdb.dbo.backupmediafamily 
INNER JOIN msdb.dbo.backupset ON msdb.dbo.backupmediafamily.media_set_id = msdb.dbo.backupset.media_set_id 
--WHERE msdb.dbo.backupset.database_name = 'ProductCatalog'
WHERE (CONVERT(datetime, msdb.dbo.backupset.backup_start_date, 102) >= GETDATE() - 7) 
--where physical_device_name like '{%'
--where msdb.dbo.backupset.backup_start_date between '2017-05-30' and '2017-05-31'
and msdb..backupset.type in ('D','I')
)
select * from BackupHistory
where FileNo = 1
ORDER BY database_name, backup_finish_date desc
 
