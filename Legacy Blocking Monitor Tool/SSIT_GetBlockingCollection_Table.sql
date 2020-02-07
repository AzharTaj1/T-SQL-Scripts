/*****
 UPDATED BY: Divya Agrawal  08/29/2001 - broke the proc for push tool to be able to pass parameters for job.
 UPDATED BY: RONNIE THOMPSON  04/09/2001
               
 CREATE DATE: 02/15/2001

 PURPOSE: CREATES Tbales OF THE BLOCKINGCOLLECTION PROCESS. CHECKS FOR 
AND CREATES ALL TABLES NEEDED FOR THE BLOCKINGCOLLECTION PROCESS */

/*
updated by yewa (Brad) on 04/17/2007
some more table definitions have been added
*/
/*
updated by yewa (Brad) on 05/02/2007
changed 3 tables' column size to [varchar](8000)
*/
USE [MetricsOps]

--=========================
--temp code for changing involved column to varchar(8000)

IF exists (select 1 from sysobjects where name = 'blocked_info' and type = 'u')
Begin
DROP table blocked_info
END
CREATE TABLE [dbo].[blocked_info](
     [spid]        [int] NOT NULL,
     [BlockerSPID] [int] NULL,
     [program_name] [varchar](255)  NOT NULL,
        [DBName]   [varchar](100)  NULL,
     [Loginame]    [varchar](255)  NULL,
     [nt_username] [varchar](255)  NULL,
     [hostname]    [varchar](100)  NULL,
     [login_time]  [datetime]    NULL,
     [last_batch]  [datetime]    NULL,
     [Date]        [datetime]    NULL,
        [RunTime_MS]    [int]         NULL,
        [Blocked_EventInfo][varchar](8000)  NULL
) ON [PRIMARY]
GO

IF exists (select 1 from sysobjects where name = 'Blocked_Event_Info' and type = 'u')
Begin
DROP table Blocked_Event_Info
END
CREATE TABLE [dbo].[Blocked_Event_Info](
     [Blocked_EventType][varchar](255)  NULL, 
     [Blocked_Parameters][varchar](255)  NULL, 
     [Blocked_EventInfo][varchar](8000)  NULL
) ON [PRIMARY]
GO

IF EXISTS (SELECT 1 FROM metricsOps.DBO.sysobjects WHERE NAME = 'Event_Info' AND type = 'U')
   BEGIN
   DROP table Event_Info
   END
   CREATE TABLE metricsOps.DBO.Event_Info(
      EventType    VARCHAR(14)    NULL,
      Parameters   INT            NULL,
      EventInfo    VARCHAR(8000)   NULL)
GO


--end of temp code
--===========================



IF NOT EXISTS (SELECT 1 FROM metricsOps.DBO.sysobjects WHERE NAME = 'EASOPS_Machine_Names' AND type = 'U')
   BEGIN
   CREATE TABLE metricsOps.DBO.EASOPS_Machine_Names(
      Name       VARCHAR(30)   NOT NULL,
      Machine1   VARCHAR(30)   NULL,
      E_Mail     VARCHAR(30)   NOT NULL)
   END
GO

IF NOT EXISTS (SELECT 1 FROM metricsOps.DBO.sysobjects WHERE NAME = 'blkinputbuf' AND type = 'U')
   BEGIN
   CREATE TABLE metricsOps.DBO.blkinputbuf (inputbuf VARCHAR (255) NULL)
   END
GO

IF NOT exists (select 1 from sysobjects where name = 'blocked_info' and type = 'u')
Begin
---DROP table blocked_info
CREATE TABLE [dbo].[blocked_info](
     [spid]        [int] NOT NULL,
     [BlockerSPID] [int] NULL,
     [program_name] [varchar](255)  NOT NULL,
        [DBName]   [varchar](100)  NULL,
     [Loginame]    [varchar](255)  NULL,
     [nt_username] [varchar](255)  NULL,
     [hostname]    [varchar](100)  NULL,
     [login_time]  [datetime]    NULL,
     [last_batch]  [datetime]    NULL,
     [Date]        [datetime]    NULL,
        [RunTime_MS]    [int]         NULL,
        [Blocked_EventInfo][varchar](8000)  NULL
) ON [PRIMARY]
END
GO

IF not exists (select 1 from sysobjects where name = 'Blocked_Event_Info' and type = 'u')
Begin
--DROP table Blocked_Event_Info
CREATE TABLE [dbo].[Blocked_Event_Info](
     [Blocked_EventType][varchar](255)  NULL, 
     [Blocked_Parameters][varchar](255)  NULL, 
     [Blocked_EventInfo][varchar](8000)  NULL
) ON [PRIMARY]
END
GO

IF NOT EXISTS (SELECT 1 FROM metricsOps.DBO.sysobjects WHERE NAME = 'Event_Info' AND type = 'U')
   BEGIN
   CREATE TABLE metricsOps.DBO.Event_Info(
      EventType    VARCHAR(14)    NULL,
      Parameters   INT            NULL,
      EventInfo    VARCHAR(8000)   NULL)
   END
GO

------------------------------
-- 6 more tables to be defined

IF NOT EXISTS (SELECT 1 FROM metricsOps.DBO.sysobjects WHERE NAME = 'locking_info' AND type = 'U')
   BEGIN
   CREATE TABLE metricsOps.DBO.locking_info(
      proc_id        INT        NULL,
      id             INT        NULL,
      dbid           INT        NULL,
      type           INT        NULL,
      number_locks   INT        NULL,
      spid           INT        NULL,
      date           DATETIME   NULL)
   END
GO

IF NOT EXISTS (SELECT 1 FROM metricsOps.DBO.sysobjects WHERE name = 'blocking_info' AND type = 'U')
   BEGIN
   CREATE TABLE metricsOps.DBO.blocking_info(
      proc_id        INT IDENTITY(1,1)   NOT NULL,
      spid           SMALLINT            NULL,
      status         CHAR(10)            NULL,
      suid           SMALLINT            NULL,
      hostname       CHAR(30)            NULL,
      program_name   CHAR(255)            NULL,
      cmd            CHAR(16)            NULL,
      cpu            INT                 NULL,
      physical_io    INT                 NULL,
      blocked        SMALLINT            NULL,
      waittype       BINARY(2)           NULL,
      dbid           SMALLINT            NULL,
      login_time     DATETIME            NULL,
      last_batch     DATETIME            NULL,
      nt_username    CHAR(30)            NULL,
      date           DATETIME            NULL,
      runtime_sec    INT                 NULL,
      inputbuffer    VARCHAR(255)        NULL,
      EventType      VARCHAR(14)         NULL,
      Parameters     INT                 NULL,
      EventInfo      VARCHAR(255)        NULL)
   END
GO

IF NOT EXISTS (SELECT 1 FROM metricsOps.DBO.sysobjects WHERE NAME = 'syslocs' AND type = 'U')
   BEGIN
   CREATE TABLE metricsOps.DBO.syslocs(
      id     INT       NOT NULL,
      dbid   SMALLINT  NOT NULL,
      page   INT       NOT NULL,
      type   SMALLINT  NOT NULL,
      spid   SMALLINT  NOT NULL)
   END
GO

IF NOT EXISTS (SELECT 1 FROM metricsOps.DBO.sysobjects WHERE name = 'Block_Alert_Action' AND type = 'U')
   BEGIN
   CREATE TABLE metricsOps.DBO.Block_Alert_Action(
      TimeNow   DATETIME   NOT NULL,
      Blocked   INT        NOT NULL,
      NetSend   CHAR(1)    NOT NULL)
   END
GO

IF NOT EXISTS (SELECT 1 FROM metricsOps.DBO.sysobjects WHERE NAME = 'blocked_current' AND type = 'U')
   BEGIN
   CREATE TABLE metricsOps.DBO.blocked_current(
      spid            INT           NOT NULL,
      hostname        VARCHAR(20)   NOT NULL,
      program_name    VARCHAR(255)   NOT NULL,
      combined_name   VARCHAR(255)   NOT NULL)
   END
GO

IF NOT EXISTS (SELECT 1 FROM metricsOps.DBO.sysobjects WHERE NAME = 'blocked_previous' AND type = 'U')
   BEGIN
   CREATE TABLE metricsOps.DBO.blocked_previous(
      spid                INT          NOT NULL,
      hostname            VARCHAR(20)  NOT NULL,
      program_name        VARCHAR(255)  NOT NULL,
      block_start_time    DATETIME     NOT NULL,
      time_blocked_secs   INT          NOT NULL,
      last_updated        DATETIME     NOT NULL,
      combined_name       VARCHAR(255)  NOT NULL)
   END
GO

IF NOT EXISTS (SELECT 1 FROM metricsOps.DBO.sysobjects WHERE NAME = 'blocked_history' AND type = 'U')
   BEGIN
   CREATE TABLE metricsOps.DBO.blocked_history(
      block_start_time    DATETIME   NOT NULL,
      spids_blocked       INT        NOT NULL,
      time_blocked_secs   INT        NOT NULL,
      block_end_time      DATETIME   NULL)
   END
GO

IF NOT EXISTS (SELECT 1 FROM metricsOps.DBO.sysobjects WHERE NAME = 'Is_Raiserror' AND type = 'U')
   BEGIN
   CREATE TABLE metricsOps.DBO.Is_Raiserror(
	Error_ID [smallint] NOT NULL,
	[IsRaiserror] [nchar](3) NOT NULL,
	Description [nvarchar](50) NULL
	)
	insert into is_raiserror values (1,'no', 'SSIT_Metrics - Blocking Collection') -- Error_ID = 1 is used for blocking collection tool
   END
GO

IF NOT EXISTS (SELECT 1 FROM metricsOps.DBO.Is_Raiserror WHERE Error_ID = 1)
   BEGIN
	insert into metricsOps.DBO.is_raiserror values (1,'no', 'SSIT_Metrics - Blocking Collection')
   END
GO


-- end of table definitions
----------------------------------------





