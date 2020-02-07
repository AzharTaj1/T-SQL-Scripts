declare @syntax_out varchar(max) 
		,@FilePath varchar(2000)
		,@DBName sysname 

set @DBName = '<Database_Name>'		-- Subsitiute database name in Getty environment that needs to be backed up.

select @FilePath = Detail02 from dbaadmin.dbo.local_control where Subject = 'backup_location_override' and Detail01 = @DBName	
if @FilePath is null
	set @FilePath = dbaadmin.[dbo].[dbaudf_GetSharePath2]('backup')		

print '-- ' + @FilePath + '\'	
exec dbaadmin.dbo.dbasp_format_BackupRestore 
			@DBName			= @DBName
			, @Mode			= 'BF' --'BL'
			, @FilePath		= @FilePath
			, @SetName		= 'Manual_Backup'
			, @SetDesc		= 'Manual_Backup'
			, @ForceCompression	= 1
			, @Verbose		= 0
			, @copyonly = 0
			, @ForceSetSize = null
			, @syntax_out		= @syntax_out output

print @syntax_out