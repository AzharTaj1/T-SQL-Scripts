USE [msdb]
GO

/****** Object:  StoredProcedure [dbo].[Db_Connection_Info]    Script Date: 06/11/2017 17:05:52 ******/
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[Db_Connection_Info]') AND type in (N'P', N'PC'))
DROP PROCEDURE [dbo].[Db_Connection_Info]
GO

USE [msdb]
GO

/****** Object:  StoredProcedure [dbo].[Db_Connection_Info]    Script Date: 06/11/2017 17:05:52 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

create proc [dbo].[Db_Connection_Info] @Db_Name nvarchar(500)
as

/* Stored proc written by Azhar Paul Taj, on June 9, 2017. */
/* This proc can be used to see detailed information about user connections coming in to a particular database, based upon data collected in
   table [msdb].[dbo].[SQL_Connections_Info].

   Usage Example:	Exec [msdb].[dbo].[Db_Connection_Info] '<Database Name>'  -- Provide a database name as a parameter value.
*/
   
select distinct Db_Name, NT_Domain, NT_Username, LoginName, Program_name, Hostname, Login_Time, Cmd, Net_Address from msdb.dbo.SQL_Connections_Info
where DB_NAME = @Db_Name
GO
