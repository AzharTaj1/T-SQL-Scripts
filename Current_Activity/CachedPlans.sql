SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

SELECT 
--TOP 100 
	CAST('<?stmt --
	'+SUBSTRING(qt.TEXT, (qs.statement_start_offset / 2) + 1, (
			(
				CASE qs.statement_end_offset
					WHEN - 1
						THEN DATALENGTH(qt.TEXT)
					ELSE qs.statement_end_offset
					END - qs.statement_start_offset
				) / 2
			) + 1)+'
	--?>' as XML) AS [Stmt_Text]
	,qt.TEXT AS [Full_Text]
	,qp.query_plan
	,db_name(qt.dbid) AS [DB_Name]
	,object_schema_name(qt.objectid, qt.dbid) + '.' + object_name(qt.objectid, qt.dbid) AS [Obj_Name]
	,qs.plan_generation_num AS recompiles
	,qs.total_elapsed_time - qs.total_worker_time AS total_wait_time
	,qs.execution_count
	,qs.total_worker_time / 1000 AS [TotalCPU_ms]
	,convert(MONEY, (qs.total_worker_time)) / (qs.execution_count * 1000) AS [AvgCPU_ms]
	,qs.total_logical_reads
	,qs.last_logical_reads
	,qs.total_logical_writes
	,qs.last_logical_writes
	,convert(MONEY, (qs.total_logical_reads + qs.total_logical_writes) / (qs.execution_count + 0.0)) AS [AvgIO]
	,convert(MONEY, (qs.total_elapsed_time)) / (qs.execution_count * 1000) AS [avg_duration_ms]
	,qs.last_elapsed_time / 1000 AS [last_duration_ms]
	,qs.last_execution_time
	,qs.creation_time
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) qt
CROSS APPLY sys.dm_exec_query_plan(qs.plan_handle) qp
WHERE qt.encrypted = 0
--and qt.text like N'%SELECT TOP(1) \[EventAsset\].\[AssetId\]%' ESCAPE '\'
and SUBSTRING(qt.TEXT, (qs.statement_start_offset / 2) + 1, (
			(
				CASE qs.statement_end_offset
					WHEN - 1
						THEN DATALENGTH(qt.TEXT)
					ELSE qs.statement_end_offset
					END - qs.statement_start_offset
				) / 2
			) + 1) like N'%SELECT TOP(1) \[EventAsset\].\[AssetId\]%' ESCAPE '\'