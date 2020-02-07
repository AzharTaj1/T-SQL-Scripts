/* This script can be used to check for Tempdb contention. */

SELECT 
       session_id,
       wait_type,
       wait_duration_ms,
       blocking_session_id,
       resource_description,
    ResourceType = Case
       When Cast(Right(resource_description, Len(resource_description) - Charindex(':', resource_description, 3)) As Int) - 1 % 8088 = 0 Then 'Is PFS Page'
                     When Cast(Right(resource_description, Len(resource_description) - Charindex(':', resource_description, 3)) As Int) - 2 % 511232 = 0 Then 'Is GAM Page'
                     When Cast(Right(resource_description, Len(resource_description) - Charindex(':', resource_description, 3)) As Int) - 3 % 511232 = 0 Then 'Is SGAM Page'
              Else 'Is Not PFS, GAM, or SGAM page' 
       End
FROM 
       sys.dm_os_waiting_tasks
WHERE 
       wait_type Like 'PAGE%LATCH_%'
And resource_description Like '2:%'
