Exec Sp_AddMessage 
  @MsgNum   = 90211,
  @Severity = 16,
  @MsgText  = '%s: Blocking threshold exceeded.  %d SPIDS, THRESHOLD = %d',
  @Lang     = Null,
  @With_Log = 'TRUE',
  @Replace  = 'Replace'

Exec Sp_AddMessage 
  @MsgNum   = 90212,
  @Severity = 16,
  @MsgText  = '%s: Continuous blocking threshold exceeded.  %d SPIDS for more than %d minutes',
  @Lang     = Null,
  @With_Log = 'TRUE',
  @Replace  = 'Replace'

USE [MetricsOps]

IF EXISTS (SELECT name FROM metricsOps.DBO.SYSOBJECTS WHERE NAME = 'SSIT_getBlockingCollection' AND type = 'P')
   BEGIN
   DROP PROCEDURE SSIT_getBlockingCollection
   END
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[SSIT_getBlockingCollection](
   @Point_Blk_Threshold   INT, 
   @Cont_Blk_Threshold    INT, 
   @Time_Threshold        INT,
   @Cycle                 SMALLINT, 
   @Cycle_Time            INT)

AS
-- OVERVIEW AND DESCRIPTION

-- -------------------------------------------------------------------------------
-- PART I:  POINT_IN_TIME BLOCKING PROCESS
--
-- 1) TO COLLECT POINT BLOCKING INFORMATION IN TABLE blocking_info 
-- 2) TO COLLECT POINT LOCKING  INFORMATION IN TABLE LOCKING_INFO
-- 3) TO RAISERROR/NETSEND IF BLOCKED SPIDS IS ABOVE @POINT_BLK_THRESHOLD
-- 
-- CREATED BY BRAD LEROSS
-- EAS OPERATIONS
-- 4/5/1999
-- -------------------------------------------------------------------------------
-- PART II: CONTINUOUS_TIME BLOCKING PROCESS
--
-- 1) TO COLLECT CONTINUOUS BLOCKING INFORMATION IN TABLE BLOCKING_history
-- 2) TO RAISERROR/NETSEND IF ** THE SAME ** @CONT_BLK_THRESHOLD OR MORE SPIDS
--    ARE BLOCKED FOR @TIME_THRESHOLD OR MORE MINUTES
--
-- PART II EXAMPLE:

-- USING @CONT_BLK_THRESHOLD = 10 AND @TIME_THRESHOLD = 3 MINUTES,
-- AN ALERT IS GENERATED IF THE SAME 10 OR MORE SPIDS ARE BLOCKED FOR 
-- 3 OR MORE MINUTES
-- 
-- CREATED BY MURLI KOUSHIK
-- 5/5/1999
-- -------------------------------------------------------------------------------
-- MODIFIED TO USE master.DBO.SYSPROCESSES AND TOOK OUT ANY VERSION LOOKUP
-- GEOFF GRISSO
-- 7/11/2000
-- -------------------------------------------------------------------------------
-- Updated by Azhar Paul Taj, so that the continous blocking time threshold would be 
-- reported correctly in error message 90212.
-- January 24, 2002.
-- -------------------------------------------------------------------------------
-- PROCEDURE ARGUMENTS:
--
-- @POINT_BLK_THRESHOLD -- POINT_IN_TIME BLOCKING THRESHOLD FOR ALERTS
-- @CONT_BLK_THRESHOLD  -- CONTINUOUS TIME BLOCKING THRESHOLD FOR ALERTS
-- @TIME_THRESHOLD      -- TIME THRESHOLD FOR ALERTING
-- @CYCLE               -- IF 5, RUNS CONTINUOUSLY COLLECTS DATA EVERY 15 SECONDS, 
--                         IF 4, TASK FIRES EVERY MINUTE WITH 4 SUBLOOPS.
-- @CYCLE_TIME          -- IF 5, THIS INTERVAL VALUE IS PARAMETRIZED, 
--                         IF 4, THIS INTERVAL VALUE IS COMPUTED BASED ON @CYCLE.
-- --------------------------------------------------------------------------------
-- FIXED ERROR SO A CONTINUOUS BLOCKING ALERT WILL NETSEND AS WELL AS RAISERROR
-- RONNIE THOMPSON
-- 02/01/2001
-- --------------------------------------------------------------------------------
-- UPDATED TO USE RAISERROR INSTEAD OF PAGE/EMAIL
-- 90211 - POINT_IN_TIME ERROR
-- 90212 - CONTINUOUS BLOCKING ERROR
-- UPDATED TO REMOVE ANY DATA COLLECTION FOR SSITWEB
-- RONNIE THOMPSON
-- 02/15/2001
-- 12/05/2003 mkoushik Modified to use substring when assigning values to local variables from sysprocesses --
--                     To prevent string truncation errors which cause job failure.
-- 04/13/2007 yewa     Modified Event_Info, blocked_info and Blocked_Event_Info to set Blocked_EventInfo column t0 2000.
-- 04/25/2007 yewa     Added IF condition to check date difference is withing INT limits when doing INSERTS into Blocking_Info and Blocked_Info.
-- 04/26/2007 yewa     Added conditions to check for Hostname = NULL or '' and CMD <> 'Chekcpoint'.

SET NOCOUNT ON

UPDATE Is_Raiserror set IsRaiserror = 'no' WHERE Error_ID = 1

DECLARE
     @active_cnt        INT,
     @blocked      INT,
     @cmd                VARCHAR(255),
     @command            VARCHAR(16),
     @count_id          INT,
     @cpu                INT,
     @date                   DATETIME,
     @dbid                   INT,
     @goaroundtime      SMALLINT,
     @hostname      VARCHAR(15),
     @id                 INT,
     @ProcID                     INT,
     @identity          INT,
     @info                   VARCHAR(255),
     @Interval_time     INT,
     @last_batch        DATETIME,
     @line                   VARCHAR(10),
     @lock_count        INT,
     @locking_fetch      INT,
     @login_time        DATETIME,
     @Machine_Name         VARCHAR(30),
     @no_locks      INT,
     @nt_username       CHAR(30),
     @paged             SMALLINT,
     @physical_io INT,
     @program_name         VARCHAR(255),
     @spid              SMALLINT,
     @status            CHAR(10),
     @suid              SMALLINT,
     @sysprocesses_cnt  INT,
     @sysspid           SMALLINT,
     @test                   VARCHAR(100),
     @total_blocked     INT,
     @type                   SMALLINT,
     @Ver               SMALLINT,
     @WaitTime      SMALLINT,
     @WaitType      BINARY(2),
     @InputBuf      VARCHAR(255), @Str               VARCHAR(255),
     @EventType         VARCHAR(14),
     @Parameters        INT,
     @EventInfo         VARCHAR(255),
     @BlockStartTime   DATETIME,
     @ZeroBlockTime      DATETIME,
     @TimeNow            DATETIME,
     @SigEventStart      DATETIME,
     @NumberSpids        INT,
     @Query_Str          VARCHAR(255),
     @Str1          varchar (2000)


-- end of table definitions
----------------------------------------

SELECT @paged = 1

-- SET UP TIME BETWEEN CYCLES IF @CYCLE <= 4 / FOR @CYCLE = 5, THIS COMES IN AS AN ARGUMENT

IF @Cycle <= 4
   BEGIN
   SELECT @Interval_Time = 60 / @Cycle
   END
ELSE
   BEGIN
   SELECT @Interval_Time = @Cycle_Time
   END

WHILE (@Cycle > 0)
BEGIN
SELECT @Date = GETDATE()

-- COLLECT BLOCKING AND LOCKING DATA AND POPULATE    THE blocking_info AND LOCKING_INFO TABLES

SELECT @sysprocesses_cnt = COUNT(spid) FROM master.DBO.sysprocesses (NOLOCK)

SELECT @active_cnt = COUNT(spid) FROM master.DBO.sysprocesses (NOLOCK) WHERE cmd != 'AWAITING COMMAND'

select * from master..sysprocesses order by spid

SELECT @total_blocked = COUNT(spid) 
     FROM master.DBO.sysprocesses (NOLOCK) 
     WHERE blocked > 0
-- 10/5/06 oliverj- DISCOUNT spids that are self-blocked latch waits
          AND spid <> blocked
          AND Cmd not like 'CHECKPOINT%'
          AND HostName is not NULL
          AND HostName != ''
          AND lastwaittype not in (
              'LATCH_NL'
              , 'LATCH_KP'
              , 'LATCH_SH'
              , 'LATCH_UP'
              , 'LATCH_EX'
              , 'LATCH_DT'
              , 'PAGELATCH_NL'
              , 'PAGELATCH_KP'
              , 'PAGELATCH_SH'
              , 'PAGELATCH_UP'
              , 'PAGELATCH_EX'
              , 'PAGELATCH_DT'
              , 'PAGEIOLATCH_NL'
              , 'PAGEIOLATCH_KP'
              , 'PAGEIOLATCH_SH'
              , 'PAGEIOLATCH_UP'
              , 'PAGEIOLATCH_EX'
              , 'PAGEIOLATCH_DT')


   IF @total_blocked > 0 -- Blocking is happening...
   BEGIN
   print 'POINT BLOCKING = ' + convert(varchar(12), @total_blocked) + ' SPID(s). '
   DECLARE blocking_curs Cursor FOR
   SELECT DISTINCT blocked FROM master.DBO.sysprocesses (NOLOCK) 
     WHERE blocked > 0
-- 10/5/06 oliverj- DISCOUNT spids that are self-blocked latch waits
          AND spid <> blocked
          AND Cmd not like 'CHECKPOINT%'
          AND HostName is not NULL
          AND HostName != ''
          AND lastwaittype not in (
              'LATCH_NL'
              , 'LATCH_KP'
              , 'LATCH_SH'
              , 'LATCH_UP'
              , 'LATCH_EX'
              , 'LATCH_DT'
              , 'PAGELATCH_NL'
              , 'PAGELATCH_KP'
              , 'PAGELATCH_SH'
              , 'PAGELATCH_UP'
              , 'PAGELATCH_EX'
              , 'PAGELATCH_DT'
              , 'PAGEIOLATCH_NL'
              , 'PAGEIOLATCH_KP'
              , 'PAGEIOLATCH_SH'
              , 'PAGEIOLATCH_UP'
              , 'PAGEIOLATCH_EX'
              , 'PAGEIOLATCH_DT')
  -- AND blocked IN (SELECT spid FROM master.DBO.sysprocesses (NOLOCK) WHERE blocked = 0)
   
   OPEN blocking_curs
      FETCH NEXT FROM blocking_curs INTO @spid
      WHILE (@@FETCH_STATUS = 0)
      BEGIN
      SELECT @cmd = 'DBCC INPUTBUFFER (' + CONVERT(VARCHAR(5), @spid) + ')'

-- added by yewa 
			 INSERT INTO metricsOps.DBO.Event_Info (EventType, Parameters, EventInfo)
			 EXEC (@cmd)
-- end added by yewa

/* 
original code:

     INSERT INTO metricsOps.DBO.Event_Info (EventType, Parameters, EventInfo)
         EXEC (@cmd)

end of original code 
*/

      SELECT @EventType  = substring( EventType, 1, 14 ),
                  @Parameters = Parameters,
                  @EventInfo  = substring( EventInfo, 1, 255 )
      FROM metricsOps.DBO.Event_Info
   
      TRUNCATE TABLE metricsOps.DBO.Event_Info
      
        SELECT @inputbuf = NULL
      
      -- GET PROCESS INFORMATION FROM SYSPROCS FOR THIS SPID
      select @status = substring ( status, 1, 10 )
           , @suid = NULL
           , @hostname = substring ( hostname, 1, 15 )
           , @program_name = substring ( program_name, 1, 255 )
           , @command = substring ( cmd, 1, 16 )
           , @cpu = cpu
           , @physical_io = physical_io
           , @blocked = @total_blocked
           , @waittype = waittype
           , @dbid = dbid
           , @login_time = login_time
           , @last_batch = last_batch
           , @nt_username = substring ( nt_username, 1, 30 )
      FROM   master.DBO.sysprocesses (NOLOCK) WHERE spid = @spid
      
      -- INSERT INTO blocking_info TABLE WITH INFORMATION FOR THIS SPID
             
      -- Check @last_batch to make sure it is not a very old date
      IF datediff ( yyyy, @last_batch, GETDATE()) > 60 set @last_batch = dateadd ( yyyy, -1, GETDATE())
      
      INSERT INTO metricsOps.DBO.blocking_info (spid, status, suid, hostname, program_name, cmd,
                      cpu, physical_io, blocked, waittype, dbid, login_time, last_batch, nt_username,
                       date, RunTime_Sec, inputbuffer, eventtype, parameters, eventinfo) 
         VALUES (@spid, @status, @suid, @hostname, @program_name, @command, @cpu,
                    @physical_io, @total_blocked, @waittype, @dbid, @login_time,
                       @last_batch, @nt_username, @date, DATEDIFF(ss, @last_batch, GETDATE()),-- changes from ss to ms -- reverted to ss 4/25/2007
                     @inputbuf, @eventtype, @parameters, substring( @eventinfo, 1, 255 ) )

----  Get DBCC input buffer for TOP 5 spids for this blocker

        declare @blocker_spid smallint
          declare @blocked_spid smallint
     declare @i_BlockedSPID_string char(50)
     declare @Myblockerspid smallint
     declare @Myblockedspid smallint
     declare @Myprogram_name varchar(255)
     declare @MydbName varchar(50)
     declare @Myloginame varchar(255)
     declare @Mynt_username varchar(255)
     declare @Myhostname varchar(255)
     declare @Mylogin_time datetime
     declare @Mylast_batch datetime
     declare @Blocked_EventType  varchar(255)
     declare @Blocked_Parameters varchar(255)
     declare @Blocked_EventInfo  varchar(2000)
     declare @RunTime_MS int
         
     SELECT @blocker_spid = @spid

                        
     select top 5 spid, blocked, program_name, name, loginame, nt_username, hostname, login_time, last_batch
     into #BlockedSPID from master..sysprocesses p, master..sysdatabases d
     where p.blocked = @blocker_spid and p.dbid = d.dbid
     order by datediff (mi, last_batch, getdate()) desc
                        
                                  
     DECLARE c_blockedSPID INSENSITIVE CURSOR FOR
     (select spid from #BlockedSPID)

     OPEN c_BlockedSPID
     FETCH NEXT FROM c_BlockedSPID INTO @blocked_spid
     WHILE (@@FETCH_STATUS = 0)
     BEGIN

              
      SELECT @i_BlockedSPID_string = 'DBCC INPUTBUFFER (' + CONVERT(VARCHAR(5), @blocked_spid) + ')'

-- added by yewa 
			  INSERT INTO metricsOps.DBO.Blocked_Event_Info (Blocked_EventType, Blocked_Parameters
						, Blocked_EventInfo)
			  EXEC (@i_BlockedSPID_string)
-- end added by yewa

--      INSERT INTO metricsOps.DBO.Blocked_Event_Info (Blocked_EventType, Blocked_Parameters
--                , Blocked_EventInfo)
--      EXEC (@i_BlockedSPID_string)

      SELECT @Blocked_EventType  = substring( Blocked_EventType, 1, 14 ),
          @Blocked_Parameters = Blocked_Parameters,
          @Blocked_EventInfo  = substring( Blocked_EventInfo, 1, 255 )
      FROM metricsOps.DBO.Blocked_Event_Info
      
      TRUNCATE TABLE metricsOps.DBO.Blocked_Event_Info
      
      
      -- GET PROCESS INFORMATION FROM SYSPROCS FOR THIS SPID
    
SELECT       @Myblockerspid = spid
           , @Myblockedspid =  blocked
           , @Myprogram_name = substring ( program_name, 1, 255 )
           , @MydbName = substring ( name, 1, 35 )
        , @Myloginame = substring (loginame,  1, 30)
        , @Mynt_username = substring (nt_username,  1, 30)
        , @Myhostname = substring (hostname, 1, 20)
           , @Mylogin_time = login_time
           , @Mylast_batch = last_batch
            FROM   #BlockedSPID WHERE spid = @blocked_spid

      -- Check @Mylast_batch to make sure it is not a very old date
      IF datediff ( dd, @Mylast_batch, GETDATE()) > 20 set @Mylast_batch = dateadd ( dd, -1, GETDATE())
      
      -- INSERT INTO blocked_info TABLE WITH INFORMATION FOR THIS BLOCKED SPID
             select @Mylast_batch
      INSERT INTO metricsOps.DBO.blocked_info (SPID, BlockerSPID, program_name 
                , dbName , loginame , nt_username , hostname , login_time , last_batch
                , date, RunTime_MS, Blocked_EventInfo) 
         VALUES ( @Myblockerspid , @Myblockedspid , @Myprogram_name , @MydbName , @Myloginame 
        , @Mynt_username  , @Myhostname , @Mylogin_time , @Mylast_batch, @date, 
         datediff (ms, @Mylast_batch, getdate()) ,  substring( @Blocked_EventInfo, 1, 255 )) 

                        
              
     FETCH NEXT FROM c_blockedSPID INTO @blocked_spid
     END
drop table #BlockedSPID
DEALLOCATE c_blockedSPID


--**********************************************
      SELECT @ProcID = @@IDENTITY -- GET 20 ROWS OF LOCKING INFORMATION FROM SYSLOCS FOR THIS SPID
      SELECT @id = MIN(id) FROM metricsOps.DBO.syslocs (NOLOCK) WHERE spid = @spid
      SELECT @count_id = 0
          WHILE @id IS NOT NULL 
          BEGIN
          SELECT @type = MIN(type) FROM metricsOps.DBO.syslocs (NOLOCK)WHERE spid = @spid AND id = @id
                WHILE @type IS NOT NULL AND @count_id <= 20
              BEGIN
              SELECT @count_id = @count_id + 1
               SELECT @dbid = dbid FROM metricsOps.DBO.syslocs (NOLOCK) WHERE spid = @spid AND id = @id
               SELECT @no_locks = COUNT(*) FROM metricsOps.DBO.syslocs (NOLOCK) WHERE spid = @spid AND id = @id AND type = @type
         
              INSERT INTO metricsOps.DBO.locking_info VALUES (@identity, @id, @dbid, @type, @no_locks, @spid, @date)
         
                        SELECT @type = MIN(type) FROM metricsOps.DBO.syslocs (NOLOCK) WHERE spid = @spid AND id = @id AND type > @type
              END  -- WHILE @TYPE IS NOT NULL
      
                -- LOOK FOR MORE LOCK INFORMATION FOR THIS SPID IF ANY
                
                   SELECT @id = MIN(id) FROM metricsOps.DBO.syslocs (NOLOCK) WHERE spid = @spid AND id > @id
          END   -- WHILE @ID IS NOT NULL
        FETCH NEXT FROM blocking_curs INTO @spid
        END   -- WHILE (@@FETCH_STATUS = 0)
   CLOSE blocking_curs
   DEALLOCATE blocking_curs
   END
     ELSE   -- @TOTAL_BLOCKED = 0
     BEGIN
     PRINT 'NO BLOCKING CURRENTLY.'
   END

-- RAISERROR/NETSEND NOT MORE THAN ONCE PER MINUTE IF BLOCKING IS ABOVE THRESHOLD

   IF @Total_Blocked >= @Point_Blk_Threshold
   BEGIN
   SELECT @BlockStartTime = MAX(TimeNow) FROM metricsOps.DBO.Block_Alert_Action WHERE NetSend = 'Y'
      IF --@paged = 1 AND 
       (DATEDIFF(mi, @BlockStartTime, @date) >= 1 ) 
      BEGIN
      SELECT @paged = 0
      END
----Viswa Test 

      IF (DATEDIFF(mi, @BlockStartTime, getdate()) < 1 ) 
      BEGIN
      SELECT @paged = 1
      END

      SELECT  @NumberSpids=Blocked FROM metricsOps.DBO.Block_Alert_Action WHERE NetSend = 'Y' and TimeNow=@BlockStartTime
     
      IF (@Total_Blocked < @NumberSpids) AND (DATEDIFF(mi, @BlockStartTime, getdate()) < 20 )
      BEGIN 
     SELECT @paged = 1
      END
 
      IF @paged = 0
      BEGIN
-- added by yewa

			print 'IN THE FIRST RAISERROR CODE, LINE 436'
			RAISERROR(90211,17,1,@@SERVERNAME,@Total_Blocked,@Point_Blk_Threshold)
			UPDATE Is_Raiserror set IsRaiserror = 'yes' WHERE Error_ID = 1

-- added by yewa
      
      INSERT INTO metricsOps.DBO.Block_Alert_Action (TimeNow, Blocked, NetSend)
        VALUES (@Date, @Total_Blocked, 'Y')
      
        SELECT @paged = 1
     END   --IF @PAGED = 0
   END   --IF @TOTAL_BLOCKED > @POINT_BLK_THRESHOLD

   -- COLLECT CONTINUOUS BLOCKING DATA AND POPULATE BLOCKED_PREVIOUS AND BLOCKED_HISTORY TABLES

     --SELECT @Paged = 0
     SELECT @TimeNow = @Date

     TRUNCATE TABLE Blocked_Current
          
     IF @Total_Blocked > 0
     BEGIN
     INSERT INTO metricsOps.DBO.Blocked_Current
        SELECT Spid, HostName, Program_Name, CONVERT(VARCHAR(6), Spid) + RTRIM(HostName) + RTRIM(Program_Name)
          FROM master.DBO.sysprocesses (NOLOCK) WHERE  Blocked != 0
-- 10/5/06 oliverj- DISCOUNT spids that are self-blocked latch waits
          AND spid <> blocked
          AND Cmd not like 'CHECKPOINT%'
          AND HostName is not NULL
          AND HostName != ''
          AND lastwaittype not in (
              'LATCH_NL'
              , 'LATCH_KP'
              , 'LATCH_SH'
              , 'LATCH_UP'
              , 'LATCH_EX'
              , 'LATCH_DT'
              , 'PAGELATCH_NL'
              , 'PAGELATCH_KP'
              , 'PAGELATCH_SH'
              , 'PAGELATCH_UP'
              , 'PAGELATCH_EX'
              , 'PAGELATCH_DT'
              , 'PAGEIOLATCH_NL'
              , 'PAGEIOLATCH_KP'
              , 'PAGEIOLATCH_SH'
              , 'PAGEIOLATCH_UP'
              , 'PAGEIOLATCH_EX'
              , 'PAGEIOLATCH_DT')
      
      IF NOT EXISTS (SELECT Spid FROM metricsOps.DBO.Blocked_Previous) -- INSERT INTO BLOCKED_PREVIOUS ALL ROWS FROM BLOCKED_CURRENT
          BEGIN
          INSERT INTO metricsOps.DBO.Blocked_Previous
             SELECT Spid, HostName, Program_Name, @TimeNow, 0, @TimeNow, Combined_Name FROM metricsOps.DBO.Blocked_Current
          END
          ELSE   -- SAVE SUMMARY DATA ON SPIDS THAT ARE NO LONGER BLOCKED
          BEGIN
          INSERT INTO metricsOps.DBO.Blocked_history (Block_Start_Time, Spids_Blocked,Time_Blocked_Secs, Block_End_Time)
             SELECT Block_Start_Time, COUNT(*) AS Spids_Blocked,DATEDIFF(ss, Block_Start_Time, Last_Updated), Last_Updated
              FROM metricsOps.DBO.Blocked_Previous BP WHERE Last_Updated > Block_Start_Time
              AND NOT EXISTS (SELECT BC.Combined_Name FROM metricsOps.DBO.Blocked_Current BC WHERE  BC.Combined_Name = BP.Combined_Name)
              GROUP  BY Block_Start_Time, Time_Blocked_Secs, DATEDIFF(ss, Block_Start_Time, Last_Updated), Last_Updated
         
          DELETE BP FROM metricsOps.DBO.Blocked_Previous BP   -- DELETE ROWS FROM BLOCKED_PREVIOUS WHICH ARE NOT IN BLOCKED_CURRENT
          WHERE NOT EXISTS (SELECT BC.Combined_Name FROM metricsOps.DBO.Blocked_Current BC WHERE  BC.Combined_Name = BP.Combined_Name)
          
          UPDATE metricsOps.DBO.Blocked_Previous   -- UPDATE TIME_BLOCKED_SECS IN BLOCKED_PREVIOUS BY ADDING INCREMENT
                SET Time_Blocked_Secs = Time_Blocked_Secs + DATEDIFF(ss, Last_Updated, @TimeNow),Last_Updated = @TimeNow
      
                INSERT INTO metricsOps.DBO.Blocked_Previous   -- INSERT INTO BLOCKED_PREVIOUS NEW ROWS FROM BLOCKED_CURRENT
             SELECT Spid, HostName, Program_Name, @TimeNow, 0, @TimeNow, Combined_Name FROM metricsOps.DBO.Blocked_Current
              WHERE NOT EXISTS (SELECT BC.Combined_Name FROM metricsOps.DBO.Blocked_Current BC, Blocked_Previous BP
                           WHERE BC.Combined_Name = BP.Combined_Name)
      
                SELECT @NumberSpids = COUNT(*) FROM metricsOps.DBO.Blocked_Previous
          WHERE Time_Blocked_Secs + 15 >= @Time_Threshold * 60   -- ALERT IF NEEDED
          print 'CONTINUOUS BLOCKING = ' + convert(varchar(12), @NumberSpids) + ' SPID(s). '

                IF @NumberSpids >= @Cont_Blk_Threshold
          BEGIN
                SELECT @BlockStartTime = MAX(TimeNow) FROM metricsOps.DBO.Block_Alert_Action WHERE NetSend = 'Y'
              IF DATEDIFF(mi, @BlockStartTime, @TimeNow) >= 1  --DATEPART(mi, @TimeNow) < 20   -- RAISERROR/NETSEND NOT MORE THAN ONCE PER MINUTE IF BLOCKING ABOVE THRESHOLD
              BEGIN
              SELECT @paged = 0
              END
              IF NOT exists (select 1 from metricsOps.DBO.Block_Alert_Action)
                BEGIN
                SELECT @paged = 0
                END
              IF @paged = 0
              BEGIN
-- added by yewa

			print 'IN THE SECOND RAISERROR CODE, LINE 529'
			RAISERROR(90212,17,1,@@SERVERNAME,@NumberSpids,@Time_Threshold)
			UPDATE Is_Raiserror set IsRaiserror = 'yes' WHERE Error_ID = 1

-- added by yewa

                 INSERT INTO metricsOps.DBO.Block_Alert_Action (TimeNow, Blocked, NetSend)
                    VALUES (@Date, @Total_Blocked, 'Y')
                         
                           SELECT @paged = 1
                END   --IF @paged = 0               
              END   --IF @NUMBERSPIDS >= @CONT_BLK_THRESHOLD
          END   --IF NOT EXISTS (SELECT SPID FROM BLOCKED_PREVIOUS)
     END   --IF @TOTAL_BLOCKED > 0
     ELSE   -- NO BLOCKING CURRENTLY, SO BLOCKED_CURRENT IS EMPTY
     BEGIN
   
   -- SAVE SUMMARY DATA ON ALL SPIDS IN BLOCKED_PREVIOUS
   
     INSERT INTO metricsOps.DBO.Blocked_history (Block_Start_Time, Spids_Blocked, Time_Blocked_Secs, Block_End_Time)
          SELECT Block_Start_Time, Count(*) as Spids_Blocked, DATEDIFF(ss, Block_Start_Time, Last_Updated), Last_Updated
          FROM metricsOps.DBO.Blocked_Previous BP WHERE Last_Updated > Block_Start_Time
          GROUP BY Block_Start_Time, Time_Blocked_Secs, DATEDIFF(ss, Block_Start_Time, Last_Updated), Last_Updated
      
     TRUNCATE TABLE metricsOps.DBO.Blocked_Previous   -- DELETE ALL ROWS FROM BLOCKED_PREVIOUS
     END
     RETURN

   -- WAIT TILL THE NEXT INTERVAL BEFORE ANOTHER PASS THROUGH THE LOOP:
   -- IF @CYCLE = 4, THEN INTERVAL IS 15 SECONDS
   -- IF @CYCLE = 2, THEN INTERVAL IS 30 SECONDS ETC.
   -- IF @CYCLE = 1, THEN INTERVAL IS 60 SECONDS BUT WE DO NOT ACTUALLY WAIT
   -- THIS VALUE IS COMPUTED AT THE BEGINNING OF THE FIRST PASS AND STORED IN @INTERVAL_TIME.
   -- IF @CYCLE = 5, THEN WE RUN CONTINUOUSLY AND @INTERVAL_TIME IS PARAMETRIZED THROUGH @CYCLE_TIME

     IF @Cycle > 1 AND @INTerval_Time < 60
     BEGIN
     SELECT @WaitTime = (@INTerval_Time * (DATEPART(ss, @date) / @INTerval_Time) + @INTerval_Time) - DATEPART(ss, @date)
     SELECT @Line = '00:00:' + 
          CASE 
          WHEN @WaitTime < 10 THEN '0' + CONVERT(CHAR(1), @WaitTime)
          ELSE CONVERT(CHAR(2), @WaitTime)
          END
     SELECT @Line, @Cycle
     WAITFOR DELAY @Line
     END
  
   -- ADJUST @CYCLE IF USING THE 4 OR FEWER PASSES PER MINUTE METHOD; DO NOTHING IF @CYCLE = 5 BECAUSE THIS MEANS RUN CONTINUOUSLY

     IF @Cycle <= 4
     BEGIN
     SELECT @Cycle = @Cycle - 1
     END
END   -- WHILE (@CYCLE > 0)

