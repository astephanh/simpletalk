-- vim: ts=2 sw=2 rnu expandtab:

USE [master]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
SET LANGUAGE us_english
GO


-- =============================================
-- Author: Tim M. Hidalgo
-- Create date: 3/8/2015
-- Disclaimer: You use this script at your own risk.  I take no responsibility if you mess things up in your production environment, I would 
-- highly recommend you take the time to read the script and understand what it is doing.  If you lose data, its on you homey.
--
--
-- Description: This stored procedure is part of automating the restore process.  This script was originally written by 
-- Greg Robidoux at http://www.mssqltips.com/sqlservertip/1584/auto-generate-sql-server-restore-script-from-backup-files-in-a-directory/
-- then modified by Jason Carter at http://jason-carter.net/professional/restore-script-from-backup-directory-modified.html to work with Ola Hallengrens scripts.
-- You can find the Ola Hallengren SQL Server Maintenance scripts at https://ola.hallengren.com/
-- I have based this on Jason Carter's script and extended it so that it can perform a point in time restore, and execute the commands
-- Debug level 1 will print variables which was more of a utility for myself while writing it, 
-- Debug level 2 will print just the commands
-- Debug level 3 will print both the variabls and the commands, and Debug NULL will execute the commands.
-- 
--
-- Example Usage:
-- dbo.sp_automate_restore @DatabaseName = 'AdventureWorks2014',
--                                        @UncPath = '\\BACKUP PATH\Used in Ola's Scripts, Inlude Servername',
--                                        @DebugLevel = 2,
--                                        @PointInTime = '20150402001601',
--                                        @NewDatabaseName = NULL,
--																				@replaceDatabaseFiles = NULL

-- dbo.sp_automate_restore @DatabaseName = 'AdventureWorks2014',
--                                        @UncPath = '\\BACKUP PATH\Used in Ola's Scripts, Inlude Servername',
--                                        @DebugLevel = 2,
--                                        @PointInTime = NULL,
--                                        @NewDatabaseName = NULL,
--																				@replaceDatabaseFiles = NULL
--
-- 04022015 - Still looking for more test cases.
-- 07222015 - Modified by Andy Garrett to allow database to be restored to new database.  To restore, pass in name of the new database using the @NewDatabaseName variable.
--          - Also modified to take into account any spaces in the name of the database, as the scripts by Ola removes spaces.  This was causing the Path to the backups to fail
--
-- 08/18/2016 - Stehan Helas
--              - check if Destination Database exists
--							- restore to physical File Name from new Database, new Parameter @replaceDatabaseFiles
--							- remove Servername from BackupDIR (easier restore on different server)
--							- ONLY Full / Log backups
--
--
-- =============================================

IF EXISTS ( SELECT  *
            FROM    sys.objects
            WHERE   object_id = OBJECT_ID(N'sp_automate_restore')
            AND type IN ( N'P', N'PC' ) ) 
DROP PROCEDURE [dbo].[sp_automate_restore]
GO


CREATE PROCEDURE [dbo].[sp_automate_restore]
    @DatabaseName VARCHAR(255)
   ,@UncPath VARCHAR(255)
   ,@DebugLevel INT = 3
   ,@PointInTime CHAR(16) = NULL
   ,@NewDatabaseName VARCHAR(255) = NULL
   ,@replaceDatabaseFiles VARCHAR(255) = NULL
AS
    BEGIN
    SET NOCOUNT ON;

		--Variable declaration.
		DECLARE @dbName sysname
		DECLARE @backupPath NVARCHAR(500)
		DECLARE @cmd NVARCHAR(500)
		DECLARE @fileList TABLE ( backupFile NVARCHAR(255))
		DECLARE @lastFullBackup NVARCHAR(500)
		DECLARE @lastDiffBackup NVARCHAR(500)
		DECLARE @backupFile NVARCHAR(500)
		DECLARE @SQL VARCHAR(MAX)
		DECLARE @DebugLevelString VARCHAR(MAX)
		DECLARE @backupDBName NVARCHAR(255)
		DECLARE @newFiles bit
		DECLARE @dbExists bit
    DECLARE @oldMDF varchar(128)
    DECLARE @oldLDF varchar(128)
    DECLARE @newMDF varchar(128)
    DECLARE @newLDF varchar(128)

		--Variable initialization
		SET @DebugLevelString = 'Debug Statement: ';
		SET @dbName = @DatabaseName
		SET @backupDBName = REPLACE(@dbName, ' ', '')
		IF (@NewDatabaseName is not NULL)
			BEGIN
				SET @dbName = @NewDatabaseName
			END
		IF (@replaceDatabaseFiles is not NULL)
			BEGIN
				SET @newFiles = 1
			END

    -- check if Database exists
		IF (not EXISTS (SELECT name FROM master.dbo.sysdatabases WHERE ('[' + name + ']' = @dbname OR name = @dbname)))
      BEGIN
		  IF (@DebugLevel = 1 OR @DebugLevel = 3) 
        PRINT @DebugLevelString + 'a new Database will be created'
      END
    ELSE
      BEGIN
        -- get physical names for  mdf and ldf
				SET @dbExists = 1
        SET @oldMDF=(SELECT physical_name FROM sys.master_files where DB_NAME(database_id) = @dbName and type = 0)
        SET @oldLDF=(SELECT physical_name FROM sys.master_files where DB_NAME(database_id) = @dbName and type = 1)
      END

		IF ((@DebugLevel = 1 OR @DebugLevel = 3) AND (@DatabaseName != @dbName))
			PRINT 'Database is being Restored to a DIFFERENT database: ' + @dbName

    SET @backupPath = @UncPath + '\' +  @backupDBName + '\FULL\'
    IF (@DebugLevel = 1 OR @DebugLevel = 3)
        PRINT @DebugLevelString + '@backupPath = ' + @backupPath;


    --Get the list of backup files
    SET @cmd = 'DIR /b ' + @backupPath
    INSERT  INTO @fileList
      (backupFile)
      EXEC master.sys.xp_cmdshell @cmd


    --Find latest full backup
    SELECT
      @lastFullBackup = MAX(backupFile)
    FROM
      @fileList
    WHERE
      backupFile LIKE '%_FULL_%'
      AND backupFile LIKE '%' + @backupDBName + '%'
    IF (@DebugLevel = 1 OR @DebugLevel = 3)
      BEGIN
        PRINT @DebugLevelString + '@lastFullBackup = ' + @lastFullBackup
      END

    BEGIN
      DECLARE @Table TABLE (LogicalName varchar(128),[PhysicalName] varchar(128), [Type] varchar, [FileGroupName] varchar(128), [Size] varchar(128), 
            [MaxSize] varchar(128), [FileId]varchar(128), [CreateLSN]varchar(128), [DropLSN]varchar(128), [UniqueId]varchar(128), [ReadOnlyLSN]varchar(128), [ReadWriteLSN]varchar(128), 
            [BackupSizeInBytes]varchar(128), [SourceBlockSize]varchar(128), [FileGroupId]varchar(128), [LogGroupGUID]varchar(128), [DifferentialBaseLSN]varchar(128), [DifferentialBaseGUID]varchar(128), [IsReadOnly]varchar(128), [IsPresent]varchar(128), [TDEThumbprint]varchar(128)
      )
      DECLARE @Path varchar(1000)='' + @backupPath + @lastFullBackup + ''
      DECLARE @LogicalNameData varchar(128),@LogicalNameLog varchar(128),@StorageFolder varchar(128)
      INSERT INTO @table
      EXEC('RESTORE FILELISTONLY FROM DISK=''' +@Path+ '''')
      SET @LogicalNameData=(SELECT LogicalName FROM @Table WHERE Type='D')
      SET @LogicalNameLog=(SELECT LogicalName FROM @Table WHERE Type='L')
      SET @StorageFolder=(SELECT PhysicalName FROM @Table where Type='D')
      SET @StorageFolder = SUBSTRING(@StorageFolder, 0, LEN(@StorageFolder) - LEN(REVERSE(SUBSTRING(REVERSE(@StorageFolder),0,CHARINDEX('\',REVERSE(@StorageFolder))))) + 1) + 'Temp\'


        
      IF (@newFiles = 1)
        BEGIN
          IF (@DebugLevel = 1)
            PRINT @DebugLevelString + 'USING Data Path from BACKUP: ' + @StorageFolder
          set @newMDF = @StorageFolder + @dbName + '.mdf'
          set @newLDF = @StorageFolder + @dbName + '.ldf'
        END
      IF (@newFiles = 0 AND @dbExists = 1)
        BEGIN
          IF (@DebugLevel = 1)
            PRINT @DebugLevelString + 'USING Data Path  from DATABASE: ' + @oldMDF
          set @newMDF = @oldMDF
          set @newLDF = @oldLDF
        END
      ELSE
        BEGIN
          -- get Data Path
          DECLARE @rc int
          DECLARE @dir nvarchar(4000) 
          exec @rc = master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE',N'Software\Microsoft\MSSQLServer\MSSQLServer',N'DefaultData', @dir output, 'no_output'
          set @newMDF = @dir + '\' + @dbName + '.mdf'
          set @newLDF = @dir + '\' + @dbName + '_log.ldf'
        END

      SET @cmd = 'RESTORE DATABASE ' + @dbName + ' FROM DISK = '''
        + @backupPath + @lastFullBackup + ''' WITH REPLACE, NORECOVERY,'
        + 'MOVE ''' + @LogicalNameData  + ''' TO ''' + @newMDF + ''', ' 
        + 'MOVE ''' + @LogicalNameLog   + ''' TO ''' + @newLDF + '''; '

    END

    --Execute the full restore command
    IF (@DebugLevel = 2 OR @DebugLevel = 3)
        PRINT @cmd
    IF (@DebugLevel IS NULL)
        EXEC sp_executesql @cmd



    --Set the path for the log backups
    SET @backupPath = @UncPath + '\' +  @backupDBName + '\LOG\'
    IF (@DebugLevel = 1 OR @DebugLevel = 3)
      PRINT @DebugLevelString + '@backupPath = ' + @backupPath


    --Declaring some variables for comparison and string manipuations
    DECLARE
      @lfb VARCHAR(255)
     ,@currentLogBackup VARCHAR(255)
     ,@previousLogBackup VARCHAR(255)
     ,@DateTimeValue VARCHAR(255);

    SELECT @lfb = REPLACE(LEFT(RIGHT(@lastFullBackup,19),15),'_','')



    --Get the list of log files that are relevant to the backups being used
    SET @cmd = 'DIR /b ' + @backupPath
    INSERT  INTO @fileList
            (backupFile)
            EXEC master.sys.xp_cmdshell @cmd
    DECLARE backupFiles CURSOR
    FOR
        SELECT
            backupFile
        FROM
            @fileList
        WHERE
            backupFile LIKE '%_LOG_%'
            AND backupFile LIKE '%' + @backupDBName + '%'
            AND REPLACE(LEFT(RIGHT(backupFile,19),15),'_','') > @lfb
        ORDER BY backupFile
    OPEN backupFiles

    -- Loop through all the files for the database
    FETCH NEXT FROM backupFiles INTO @backupFile
    SET @previousLogBackup = REPLACE(LEFT(RIGHT(@backupFile,19),15),'_','')
    SET @lastFullBackup = REPLACE(LEFT(RIGHT(@lastFullBackup,19),15),'_','')
    IF (@PointInTime < @lastFullBackup)
      BEGIN
          PRINT 'Invalid @PointInTime.  Must be a value greater than the last full or diff backup'
          RETURN -1;
      END

    WHILE @@FETCH_STATUS = 0
      BEGIN
        SET @currentLogBackup = REPLACE(LEFT(RIGHT(@backupFile,19),15),'_','')
        IF (@DebugLevel = 1 OR @DebugLevel = 3)
            PRINT @DebugLevelString + 'Last Log Backup: ' + @currentLogBackup + ' Last Full Backup: ' + @lfb
        IF (@PointInTime IS NULL)
            BEGIN
                IF (@currentLogBackup > @lfb)
                    BEGIN
                        SET @cmd = 'RESTORE LOG ' + @dbName
                            + ' FROM DISK = ''' + @backupPath
                            + @backupFile + ''' WITH REPLACE, NORECOVERY'
                        IF (@DebugLevel = 2 OR @DebugLevel = 3)
                            PRINT @cmd
        --Execute the log restores commands
                        IF (@DebugLevel IS NULL)
                            EXEC sp_executesql @cmd
                    END
            END
        ELSE
            IF (@currentLogBackup < @PointInTime)
                BEGIN
                    SET @cmd = 'RESTORE LOG ' + @dbName
                        + ' FROM DISK = ''' + @backupPath
                        + @backupFile + ''' WITH NORECOVERY'
                    IF (@DebugLevel = 2 OR @DebugLevel = 3)
                        PRINT @cmd
      --Execute the log restores commands
                    IF (@DebugLevel IS NULL)
                        EXEC sp_executesql @cmd
                END
            ELSE
        IF ((@PointInTime > @previousLogBackup
            AND @PointInTime < @currentLogBackup) OR @PointInTime < @previousLogBackup
           )
            BEGIN
                SET @DateTimeValue = CONVERT(VARCHAR,CONVERT(DATETIME,
                      SUBSTRING(@PointInTime,1,8)),111) + ' '
                    + SUBSTRING(@PointInTime,9,2) + ':'
                    + SUBSTRING(@PointInTime,11,2) + ':'
                    + SUBSTRING(@PointInTime,13,2)
                SET @cmd = 'RESTORE LOG ' + @dbName
                    + ' FROM DISK = ''' + @backupPath + @backupFile
                    + ''' WITH NORECOVERY, STOPAT = '''
                    + @DateTimeValue + ''''
                IF (@DebugLevel = 2 OR @DebugLevel = 3)
                    PRINT @cmd
      --Execute the log restores commands
                IF (@DebugLevel IS NULL)
                    EXEC sp_executesql @cmd
      END
      SET @previousLogBackup = @currentLogBackup 
      FETCH NEXT FROM backupFiles INTO @backupFile
    END
    CLOSE backupFiles
    DEALLOCATE backupFiles


    --End with recovery so that the database is put back into a working state.
    SET @cmd = 'RESTORE DATABASE ' + @dbName + ' WITH RECOVERY'
    IF (@DebugLevel = 2 OR @DebugLevel = 3)
      PRINT @cmd
    IF (@DebugLevel IS NULL)
      EXEC sp_executesql @cmd
    END

