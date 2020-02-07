-- DROP INDEX STATEMENT

SELECT 
	'DROP INDEX ' +   QuoteName(Schema_name(T.Schema_id)) + '.' + QuoteName(T.name) + '.' + QuoteName(I.name) [DropIndexScript]
FROM sys.indexes I     
JOIN sys.tables T ON T.Object_id = I.Object_id      
WHERE I.is_primary_key = 0 AND I.is_unique_constraint = 0   
--AND I.Object_id = object_id('Person.Address') --Comment for all tables   
--AND I.name = 'IX_Address_PostalCode' --comment for all indexes
and T.name    NOT IN ('dtproperties')
and T.name	NOT LIKE 'MS%'
and T.name	NOT LIKE 'sysmerge%'

-- CREATE INDEX STATEMENT

SELECT 
	'CREATE ' +   
    CASE WHEN I.is_unique = 1 THEN ' UNIQUE ' ELSE '' END  + I.type_desc COLLATE DATABASE_DEFAULT +' INDEX ' +     
    QuoteName(I.name ) + ' ON '  +    
    QuoteName(Schema_name(T.Schema_id)) + '.' + QuoteName(T.name) + ' ( ' + KeyColumns.list + ' ) ' +   
    ISNULL(' INCLUDE (' + IncludedColumns.list + ') ','') +   
    ISNULL(' WHERE ' + I.Filter_definition,'') + ' WITH ( ' +   
    CASE WHEN I.is_padded = 1 THEN ' PAD_INDEX = ON ' ELSE ' PAD_INDEX = OFF ' END + ','  +   
    'FILLFACTOR = ' + CONVERT(CHAR(5),CASE WHEN I.Fill_factor = 0 THEN 100 ELSE I.Fill_factor END) + ','  +   
    -- default value   
    --'SORT_IN_TEMPDB = OFF '  + ','  +   
    CASE WHEN I.ignore_dup_key = 1 THEN ' IGNORE_DUP_KEY = ON ' ELSE ' IGNORE_DUP_KEY = OFF ' END + ','  +   
    CASE WHEN ST.no_recompute = 0  THEN ' STATISTICS_NORECOMPUTE = OFF ' ELSE ' STATISTICS_NORECOMPUTE = ON ' END + ','  +   
    -- default value    
    -- ' DROP_EXISTING = ON '  + ','  +   
    -- default value    
    ' ONLINE = OFF '  + ','  +   
   CASE WHEN I.allow_row_locks = 1  THEN ' ALLOW_ROW_LOCKS = ON '  ELSE ' ALLOW_ROW_LOCKS = OFF ' END + ','  +   
   CASE WHEN I.allow_page_locks = 1 THEN ' ALLOW_PAGE_LOCKS = ON ' ELSE ' ALLOW_PAGE_LOCKS = OFF ' END  + 
   ' ) ON ' + 
   QuoteName(DS.name)  [CreateIndexScript]   
FROM sys.indexes I     
JOIN sys.tables T ON T.Object_id = I.Object_id      
JOIN sys.sysindexes SI ON I.Object_id = SI.id AND I.index_id = SI.indid     
CROSS APPLY (	SELECT 
					CASE WHEN IC1.index_column_id = 1 THEN '' ELSE ', ' END + 
					QuoteName(C.name) + CASE WHEN CONVERT(INT,IC1.is_descending_key) = 1 THEN ' DESC ' ELSE ' ASC ' END 
    			FROM sys.index_columns IC1    
    			JOIN Sys.columns C     
       				ON C.object_id = IC1.object_id     
       				AND C.column_id = IC1.column_id     
       				AND IC1.is_included_column = 0    
    			WHERE IC1.object_id = I.object_id     
       				AND IC1.index_id = I.index_id     
    			ORDER BY IC1.index_column_id
       			FOR XML PATH('')
	) KeyColumns (list)
CROSS APPLY (	SELECT 
					CASE WHEN IC1.index_column_id = min(IC1.index_column_id) OVER (PARTITION BY IC1.object_id) THEN '' ELSE ', ' END + 
					QuoteName(C.name)
    			FROM sys.index_columns IC1    
    			JOIN Sys.columns C     
       				ON C.object_id = IC1.object_id     
       				AND C.column_id = IC1.column_id     
       				AND IC1.is_included_column = 1    
    			WHERE IC1.object_id = I.object_id     
       				AND IC1.index_id = I.index_id     
    			ORDER BY IC1.index_column_id
       			FOR XML PATH('')
	) IncludedColumns (list)
JOIN sys.stats ST ON ST.object_id = I.object_id AND ST.stats_id = I.index_id     
JOIN sys.data_spaces DS ON I.data_space_id=DS.data_space_id     
JOIN sys.filegroups FG ON I.data_space_id=FG.data_space_id     
WHERE I.is_primary_key = 0 AND I.is_unique_constraint = 0   
--AND I.Object_id = object_id('Person.Address') --Comment for all tables   
--AND I.name = 'IX_Address_PostalCode' --comment for all indexes
and T.name    NOT IN ('dtproperties')
and T.name	NOT LIKE 'MS%'
and T.name	NOT LIKE 'sysmerge%'
