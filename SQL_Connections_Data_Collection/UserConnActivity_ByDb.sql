/* Provides number of user connections activity for the SQL server, per user database. */

select Db_Name, Connection_Count = COUNT(Db_Name) from [msdb].[dbo].[SQL_Connections_Info] with (nolock)
where 
	Db_Name not in ('master', 'model', 'msdb', 'tempdb')
group by Db_Name
order by 2 desc