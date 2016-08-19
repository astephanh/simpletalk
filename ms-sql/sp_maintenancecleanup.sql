-- the definition of the procedure.
-- Author:		<Stephan,Helas>

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE dbo.CommandLogCleanup
AS
BEGIN
	SET NOCOUNT ON;
	DELETE FROM [dbo].[CommandLog] WHERE StartTime < DATEADD(dd,-30,GETDATE());
END
GO

