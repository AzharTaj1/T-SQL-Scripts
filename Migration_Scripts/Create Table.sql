select  
	'CREATE TABLE ' + QuoteName(so.name) + ' (' + o.list + CHAR(10) + ')' + 
	CASE WHEN tc.Constraint_Name IS NULL THEN '' 
		ELSE CHAR(10) + 'ALTER TABLE ' + QuoteName(so.Name) + ' ADD CONSTRAINT ' + QuoteName(tc.Constraint_Name)  + ' PRIMARY KEY ' + ' (' + LEFT(j.List, Len(j.List)-1) + ')' 
	END 
	+ ISNULL(replace(replace(cc.list,'&gt;','>'),'&lt;','<'), '') + CHAR(10)
from    sysobjects so
cross apply
    (SELECT 
        char(10) + 
		'  '+QuoteName(col.column_name) + 
        col.data_type + case col.data_type
            when 'sql_variant' then ''
            when 'text' then ''
            when 'ntext' then ''
            when 'xml' then ''
            when 'decimal' then '(' + cast(col.numeric_precision as varchar) + ', ' + cast(col.numeric_scale as varchar) + ')'
            else coalesce('('+case when col.character_maximum_length = -1 then 'MAX' else cast(col.character_maximum_length as varchar) end +')','') end + ' ' +
        case 
			when exists ( 
				select id from syscolumns
				where object_name(id)=so.name
				and name=column_name
				and columnproperty(id,name,'IsIdentity') = 1 )
			then
				'IDENTITY(' + 
				cast(ident_seed(so.name) as varchar) + ',' + 
				cast(ident_incr(so.name) as varchar) + ')'
	        else ''
		end + ' ' +
		case when col.IS_NULLABLE = 'No' then 'NOT ' else '' end  + 'NULL ' + 
		case when col.COLUMN_DEFAULT IS NOT NULL THEN 'DEFAULT '+ col.COLUMN_DEFAULT ELSE '' END + 
		case when ordinal_position = max(ordinal_position) over (partition by table_name) then '' else ', ' end
	from information_schema.columns col
	where col.table_name = so.name
	order by ordinal_position
	FOR XML PATH('')
	) o (list)
left join
    information_schema.table_constraints tc
		on  tc.Table_name       = so.Name
		AND tc.Constraint_Type  = 'PRIMARY KEY'
cross apply
	(select CHAR(10) + 'ALTER TABLE ' +    QuoteName(OBJECT_NAME(sysconstraints.id)) + ' ADD CONSTRAINT ' + QuoteName(cc.Constraint_Name) + ' CHECK ' + Check_Clause
	from sysconstraints 
	join information_schema.check_constraints cc
		on cc.CONSTRAINT_NAME = object_name(sysconstraints.constid)
	where object_name(sysconstraints.id) = so.Name
	for xml path('')
	) cc (list)
cross apply
    (select '[' + Column_Name + '], '
     FROM   information_schema.key_column_usage kcu
     WHERE  kcu.Constraint_Name = tc.Constraint_Name
     ORDER BY
        ORDINAL_POSITION
     FOR XML PATH('')
	 ) j (list)
where   xtype = 'U'
and name    NOT IN ('dtproperties')
and name	NOT LIKE 'MS%'
and name	NOT LIKE 'sysmerge%'
--and (name = 'Currency' or name = 't1')

/*

select object_name(constid), object_name(id), status & 4, status & 5, *
from sysconstraints 
where object_name(id) = 'Currency'


select max(ordinal_position) over (partition by table_name) max_op, *
from information_schema.table_constraints

select * from information_schema.columns


select max(ordinal_position) over (partition by table_name) max_op, *
from information_schema.columns 

select * from information_schema.TABLE_PRIVILEGES
select * from information_schema.key_column_usage 
*/


/*
alter table Currency add constraint CH_Currency_int3 CHECK (int3 between -10000 and 10000)
alter table Currency add constraint CH_Currency_int2 CHECK (int2 > 0)
select * from Currency
select * from information_schema.columns where table_name = 'Currency'


select * 
FROM
    INFORMATION_SCHEMA.CHECK_CONSTRAINTS cc



SELECT
    'ALTER TABLE  ' +
    QuoteName(OBJECT_NAME(so.parent_obj)) +
    CHAR(10) +
    ' DROP CONSTRAINT ' +
    QuoteName(CONSTRAINT_NAME)
FROM
    INFORMATION_SCHEMA.CHECK_CONSTRAINTS cc
    INNER JOIN sys.sysobjects so
    ON cc.CONSTRAINT_NAME = so.[name]

-- Recreate Check Constraints
SELECT
    'ALTER TABLE  ' +
    QuoteName(OBJECT_NAME(so.parent_obj)) +
    CHAR(10) +
    ' ADD CONSTRAINT ' +
    QuoteName(CONSTRAINT_NAME) +
    ' CHECK ' +
    CHECK_CLAUSE
FROM
    INFORMATION_SCHEMA.CHECK_CONSTRAINTS cc
    INNER JOIN sys.sysobjects so
    ON cc.CONSTRAINT_NAME = so.[name]

create table t1(
int2 int null CONSTRAINT [CH_t1_int2] CHECK ([int2]>(0)) CONSTRAINT [DF_t1_int2] DEFAULT (0)
)
drop table t1

select * from     information_schema.table_constraints tc

*/
