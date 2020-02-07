 /****
UPDATED BY: oliverj	04/20/07 - changed retry to 3 for step 1.
UPDATED BY: Divya Agrawal  08/29/2001 - broke the proc for push tool to be able to pass parameters for job.
UPDATED BY: RONNIE THOMPSON  04/09/2001              
CREATE DATE: 02/15/2001
CREATE THE METRICS - BLOCKING COLLECTION JOB WITH DEFAULT PARAMETERS. 
FIRST LETS DELETE THE OLD JOBS  ****/

-- LETS CREATE THE NEW SSIT_METRICS - BLOCKING COLLECTION JOB
BEGIN TRANSACTION            
  DECLARE @JobID BINARY(16)  
  DECLARE @ReturnCode INT    
  SELECT @ReturnCode = 0     
IF (SELECT COUNT(*) FROM msdb.dbo.syscategories WHERE name = N'SSITOPS.net') < 1 
  EXECUTE msdb.dbo.sp_add_category @name = N'SSITOPS.net'

-- DELETE THE JOB WITH THE SAME NAME (IF IT EXISTS)
  SELECT @JobID = job_id     
  FROM   msdb.dbo.sysjobs    
  WHERE (name = N'SSIT_Metrics - Blocking Collection')       
  IF (@JobID IS NOT NULL)    
	  BEGIN  
	  -- CHECK IF THE JOB IS A MULTI-SERVER JOB  
	  IF (EXISTS (SELECT  * 
				  FROM    msdb.dbo.sysjobservers 
				  WHERE   (job_id = @JobID) AND (server_id <> 0))) 
	  BEGIN 
		-- THERE IS, SO ABORT THE SCRIPT 
		RAISERROR (N'Unable to import job ''SSIT_Metrics - Blocking Collection'' since there is already a multi-server job with this name.', 16, 1) 
		GOTO QuitWithRollback  
	  END 
	  ELSE 
		-- DELETE THE [LOCAL] JOB 
		EXECUTE msdb.dbo.sp_delete_job @job_name = N'SSIT_Metrics - Blocking Collection' 
		SELECT @JobID = NULL
	  END 

BEGIN 
  -- ADD THE JOB
  EXECUTE @ReturnCode          = msdb.dbo.sp_add_job
	@job_id                = @JobID OUTPUT,
	@job_name              = N'SSIT_Metrics - Blocking Collection',
	@owner_login_name      = N'sa',
	@description           = N'Job for blocking alerts.',
	@category_name         = N'SSITOPS.net',
	@enabled               = 1,
	@notify_level_email    = 0,
	@notify_level_page     = 0,
	@notify_level_netsend  = 0,
	@notify_level_eventlog = 2,
	@delete_level          = 0
  IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

  -- ADD THE JOB STEPS
/*
EXECUTE @ReturnCode = msdb.dbo.sp_add_jobstep 
	@job_id = @JobID, 
	@step_id = 1, 
	@step_name = N'SSIT_getBlockingCollection', 
	@command = N'Exec MetricsOps.dbo.SSIT_GetBlockingCollection 
	@Point_Blk_Threshold = 30, 	-- Point_in_Time Blocking Threshold.
	@Cont_Blk_Threshold = 5, 	-- Continuous blocking threshold
	@Time_Threshold = 3, 		-- Time threshold for continuous blocking
	@Cycle = 4, 
	@Cycle_Time = 30', 
	@database_name 	= N'MetricsOps', 
	@server 		= N'', 
	@database_user_name 	= N'', 
	@subsystem 		= N'TSQL', 
	@cmdexec_success_code 	= 0, 
	@flags 			= 0, 
	@retry_attempts 	= 0, 
	@retry_interval 	= 1, 
	@output_file_name 	= N'', 
	@on_success_step_id 	= 0, 
	@on_success_action 	= 1, 
	@on_fail_step_id 	= 0, 
	@on_fail_action 	= 2*/

-- add job step 1
EXECUTE @ReturnCode           = msdb.dbo.sp_add_jobstep 
	@job_id               = @JobID, 
	@step_id              = 1,
	@step_name            = N'SSIT_getBlockingCollection', 
	@command              = N'EXEC MetricsOps.DBO.SSIT_getBlockingCollection 20, 10, 5, 4, 30',
	@database_name        = N'MetricsOps',
	@server               = N'',
	@database_user_name   = N'',
	@subsystem            = N'TSQL',
	@cmdexec_success_code = 0,
	@flags                = 4,
	@retry_attempts       = 0,
	@retry_interval       = 1,
	@output_file_name     = N'',
	@on_success_step_id   = 0,
	@on_success_action    = 1,
	@on_fail_step_id      = 0,
	@on_fail_action = 3


  IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

-- add job step 2
EXECUTE @ReturnCode           = msdb.dbo.sp_add_jobstep 
	@job_id               = @JobID, 
	@step_id              = 2,
	@step_name            = N'Job outcome Success/Failure logic', 
	@database_name        = N'MetricsOps',
	@server               = N'',
	@database_user_name   = N'',
	@subsystem            = N'TSQL',
	@cmdexec_success_code = 0,
	@flags                = 4,
	@retry_attempts       = 0,
	@retry_interval       = 1,
	@output_file_name     = N'',
	@on_success_step_id   = 0,
	@on_success_action    = 1,
	@on_fail_step_id      = 0,
	@on_fail_action = 2,
	@command=N'
USE [MetricsOps]


if exists(select Error_ID from Is_Raiserror where IsRaiserror = ''yes'' and Error_ID = 1)
        UPDATE Is_Raiserror set IsRaiserror = ''no'' where Error_ID = 1
else
        raiserror (''The job failed due to a non-blocking issue'', 16, 1) -- this problematic code is added on purpose for alerting purpose by Murli and yewa
'


  IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
 
  EXECUTE @ReturnCode    = msdb.dbo.sp_update_job 
          @job_id        = @JobID, 
          @start_step_id = 1 

  IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
  -- ADD THE JOB SCHEDULES
   EXECUTE @ReturnCode           = msdb.dbo.sp_add_jobschedule
	@job_id                  = @JobID,
	@name                    = N'Blocking Metrics',
	@enabled = 1, @freq_type = 4,
	@active_start_date       = 20000111,
	@active_start_time       = 0,
	@freq_interval           = 1,
	@freq_subday_type        = 4,
	@freq_subday_interval    = 1,
	@freq_relative_interval  = 0,
	@freq_recurrence_factor  = 0,
	@active_end_date         = 99991231,
	@active_end_time         = 235959
  IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
  -- ADD THE TARGET SERVERS
  EXECUTE @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @JobID, @server_name = N'(local)' 
  IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback 

END
COMMIT TRANSACTION          
GOTO   EndSave              
QuitWithRollback:
  IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION 
EndSave:

GO
