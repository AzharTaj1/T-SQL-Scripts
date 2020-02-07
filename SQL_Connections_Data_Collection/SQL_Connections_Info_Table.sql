USE [msdb]
GO

/****** Object:  Table [dbo].[SQL_Connections_Info]    Script Date: 06/11/2017 16:17:02 ******/
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[SQL_Connections_Info]') AND type in (N'U'))
DROP TABLE [dbo].[SQL_Connections_Info]
GO

USE [msdb]
GO

/****** Object:  Table [dbo].[SQL_Connections_Info]    Script Date: 06/11/2017 16:17:02 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE TABLE [msdb].[dbo].[SQL_Connections_Info](
	[Db_Name] [nvarchar](500) NULL,
	[NT_Domain] [nvarchar](500) NULL,
	[NT_Username] [nvarchar](500) NULL,
	[LoginName] [nvarchar](500) NULL,
	[Program_Name] [nvarchar](500) NULL,
	[HostName] [nvarchar](500) NULL,
	[Login_Time] [nvarchar](100) NULL,
	[Cmd] [nvarchar](500) NULL,
	[Net_Address] [nvarchar](500) NULL
) ON [PRIMARY]
GO