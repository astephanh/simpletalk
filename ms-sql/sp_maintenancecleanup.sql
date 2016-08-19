/*
 * sp_maintenancecleanup.sql
 * Copyright (C) 2016 Stephan Helas <stephan.helas@pp-nt.com>
 *
 * Distributed under terms of the MIT license.
 */

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

IF EXISTS ( SELECT  *
            FROM    sys.objects
            WHERE   object_id = OBJECT_ID(N'CommandLogCleanup')
            AND type IN ( N'P', N'PC' ) ) 
DROP PROCEDURE [dbo].[CommandLogCleanup]
GO

CREATE PROCEDURE [dbo].[CommandLogCleanup]
AS
BEGIN
	SET NOCOUNT ON;
	DELETE FROM [dbo].[CommandLog] WHERE StartTime < DATEADD(dd,-30,GETDATE());
END
GO

-- vim:et sw=2 ts=2 expandtab:
