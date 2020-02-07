use master
go
if exists (select
               *
           from
               information_schema.ROUTINES
           where
              ROUTINE_NAME = 'sp_blocked_by'
              and ROUTINE_SCHEMA = 'dbo')
    drop proc [dbo].[sp_blocked_by]
go
------------------------------------------------------------------ Define SP --

-- [dbo].[sp_blocked_by]
    declare
    @latch      int = 0
    ,@fast      int = 0
    ,@ignoreApp sysname = ''
    

    set nocount on
    set language 'us_english'
begin
    select
        des.SESSION_ID                                         as [root blocking session id]
        ,der.STATUS                                            as [blocking session request status]
        ,des.LOGIN_TIME                                        as [blocking session login time]
        ,des.LOGIN_NAME                                        as [blocking session login name]
        ,des.HOST_NAME                                         as [blocking session host name]
        ,coalesce(der.START_TIME, des.LAST_REQUEST_START_TIME) as [request start time]
        ,case
             when des.LAST_REQUEST_END_TIME >= des.LAST_REQUEST_START_TIME then des.LAST_REQUEST_END_TIME
             else null
         end                                                   as [request end time]
        ,substring(TEXT, der.STATEMENT_START_OFFSET / 2, case
                                                             when der.STATEMENT_END_OFFSET = -1 then datalength(TEXT)
                                                             else der.STATEMENT_END_OFFSET / 2
                                                         end)  as [executing command]
        ,case
             when der.SESSION_ID is null then 'Blocking session does not have an open request and may be due to an uncommitted transaction.'
             when der.WAIT_TYPE is not null then 'Blocking session is currently experiencing a '
                                                 + der.WAIT_TYPE + ' wait.'
             when der.STATUS = 'Runnable' then 'Blocking session is currently waiting for CPU time.'
             when der.STATUS = 'Suspended' then 'Blocking session has been suspended by the scheduler.'
             else 'Blocking session is currently in a '
                  + der.STATUS + ' status.'
         end                                                   as [blocking notes]
    from
        Sys.DM_EXEC_SESSIONS des (READUNCOMMITTED)
    left join   Sys.DM_EXEC_REQUESTS der (READUNCOMMITTED) on
        der.SESSION_ID = des.SESSION_ID
    outer Apply Sys.DM_Exec_Sql_Text(der.SQL_HANDLE)
    where
        des.SESSION_ID in (select
                               BLOCKING_SESSION_ID
                           from
                               Sys.DM_EXEC_REQUESTS (READUNCOMMITTED)
                           where
                              BLOCKING_SESSION_ID <> 0
                              and BLOCKING_SESSION_ID not in (select
                                                                  SESSION_ID
                                                              from
                                                                  Sys.DM_EXEC_REQUESTS (READUNCOMMITTED)
                                                              where
                                                                 BLOCKING_SESSION_ID <> 0))

   
end -- sp_blocked_by
go 
