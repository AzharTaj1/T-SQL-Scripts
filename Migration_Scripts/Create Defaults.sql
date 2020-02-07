SELECT
    'ALTER TABLE ' + QUOTENAME(SCHEMA_NAME(st.schema_id)) + '.' + QuoteName(OBJECT_NAME(sc.id)) + ' DROP CONSTRAINT ' + QuoteName(OBJECT_NAME(sc.cdefault)),
	'ALTER TABLE ' + QUOTENAME(SCHEMA_NAME(st.schema_id)) + '.' + QuoteName(OBJECT_NAME(sc.id)) + ' WITH NOCHECK ADD CONSTRAINT ' +
		QuoteName(OBJECT_NAME(sc.cdefault)) + ' DEFAULT ' + sm.text + ' FOR ' + QuoteName(sc.name)
FROM syscolumns sc
JOIN sysobjects as so on sc.cdefault = so.id
JOIN syscomments as sm on sc.cdefault = sm.id
JOIN sys.tables as st on st.object_id = so.parent_obj
WHERE so.xtype = 'D'
    
