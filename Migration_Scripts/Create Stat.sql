/*
#function: on local instance, scripting out [AdventureWorks2012] db auto-created statistics (those stats for indexes are created with the indexes, so no worry needed)
#the generated file is put at c:\temp\stats_auto.sql

import-module sqlps -DisableNameChecking;

foreach ($t in (dir sqlserver:\sql\localhost\default\databases\AdventureWorks2012\Tables))
{
    $t.Statistics | ? { $_.IsAutoCreated} | % { "create statistics $($_.name) on [$($t.schema)].[$($t.name)] ( $($_.statisticColumns -join ',') )" } | Out-File c:\temp\stats_auto.sql -append; 
}
*/

SELECT DISTINCT
SCHEMA_NAME(obj.schema_id) as [Schema],
obj.[name]  AS TableName,
s.name AS StatName,
s.stats_id,
STATS_DATE(s.[object_id], s.stats_id) AS LastUpdated,
s.auto_created,
s.user_created,
s.no_recompute,

s.is_temporary,
s.filter_definition, -- not compatible with sql 2005
s.[object_id],
DROP_SCRIPT = 'DROP STATISTICS ' + QUOTENAME(SCHEMA_NAME(obj.schema_id)) + '.' + QUOTENAME(obj.[name]) + '.' + QUOTENAME(S.NAME),
THE_SCRIPT='CREATE STATISTICS ' + QUOTENAME(S.NAME) + 
           ' ON ' + QUOTENAME(SCHEMA_NAME(obj.schema_id)) + '.' + QUOTENAME(obj.[name]) + 
           '(' +
            STUFF( ( SELECT ', ' + 
                           QUOTENAME(c.name)

                          FROM sys.stats_columns sc 

                    INNER JOIN sys.columns c 
                            ON c.[object_id] = sc.[object_id] 
                           AND c.column_id = sc.column_id

                        WHERE sc.[object_id] = s.[object_id] 
                          AND sc.stats_id = s.stats_id

                    ORDER BY sc.stats_column_id 
                    FOR XML PATH('')),1 ,1, '') +
          ')' +
        ISNULL(' WHERE ' + filter_definition,'') +
        ISNULL(STUFF ( 
            --ISNULL(',STATS_STREAM = ' + @StatsStream, '') +
            CASE WHEN no_recompute = 1   THEN ',NORECOMPUTE'    ELSE '' END 

         , 1 , 1 ,  ' WITH '  ) , '')

FROM sys.stats s 

INNER JOIN sys.partitions par 
        ON par.[object_id] = s.[object_id]

INNER JOIN sys.objects obj 
        ON par.[object_id] = obj.[object_id]

WHERE OBJECTPROPERTY(s.OBJECT_ID,'IsUserTable') = 1
AND (s.auto_created = 1 OR s.user_created = 1)
