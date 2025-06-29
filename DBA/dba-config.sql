C/*****************************************************************
                 ----------------------- 
                 T-SQLtools - DBA-Config
                 -----------------------

DESCRIPTION: This is a simple T-SQL query to configure your SQL 
Server with Best Practices. After install SQL Server/Any exsiting 
SQL Server you can Run this. 

Parameters:

MinMem        	=> Assign Minimum Memory [Default 0]       
MaxMem        	=> Assign Maximum  Memory [Default 90%]       
P_MAXDOP      	=> Set Max Degree of Parallelism [ Default - Based on CPU Cores]
CostThresHold 	=> Cost value to use Parallelism [Default - 50]
DBfile        	=> Default Data files [Default - Current Data file location]           
Logfile       	=> Default Log files [Default- Current Log file location]            
Backup        	=> Default path for Backup files [Default - Current Data backup location ]
TempfilePath	=> Path for adding tempDB files [Default - Current Temp mdf file path]
TempfileSize	=> Size for new temp DB files [Default - 100MB]


Other Parameters will Reset to Default:
1. index create memory = 0
2. min memory per query = 1024
3. priority boost = 0
4. max worker threads = 0
5. lightweight pooling = 0
6. fill factor = 0
7. backup compression default = 1



Credits: This Max_DOP value query written by Kin 
https://dba.stackexchange.com/users/8783/kin


Version: v1.0 
Release Date: 2018-02-12
Author: Bhuvanesh(@SQLadmin)
Feedback: mailto:r.bhuvanesh@outlook.com
Blog: www.sqlgossip.com
License:  GPL-3.0
(C) 2018

*************************
Here is how I executed?
*************************

DECLARE @MinMem int -- Let the query calculate this        
DECLARE @MaxMem int -- Let the query calculate this        
DECLARE @P_MAXDOP INT -- Let the query calculate this      
DECLARE @CostThresHold INT -- Let the query calculate this 
DECLARE @DBfile nvarchar(500) = 'C:\Data'                  
DECLARE @Logfile nvarchar(500) =  'C:\Log'                 
DECLARE @Backup NVARCHAR(500) = 'C:\backups\'              
DECLARE @TempfilePath nvarchar(500) = 'C:\temp\'           
DECLARE @TempfileSize nvarchar(100) = '100MB' 

******************************************************************/

-- ========================================
-- SQL Server Configuration Script
-- ========================================

-- Variable Declarations & Initialization
-- ========================================
-- SQL Server Configuration Script
-- ========================================

-- Variable Declarations & Initialization
DECLARE 
    @MinMem INT = 0,
    @MaxMem INT = 90,
    @P_MAXDOP INT,
    @CostThreshold INT = 50,
    @DBfile NVARCHAR(500),
    @Logfile NVARCHAR(500),
    @Backup NVARCHAR(500),
    @TempfilePath NVARCHAR(500), -- MANDATORY: Set before execution
    @TempfileSize NVARCHAR(100) = '100MB',
    @MaximumMemory INT;

-- Enable advanced options
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;

-- ==========================
-- General Best Practice Settings
-- ==========================
EXEC sp_configure 'index create memory', 0;
RECONFIGURE;
EXEC sp_configure 'min memory per query', 1024;
RECONFIGURE;
EXEC sp_configure 'priority boost', 0;
RECONFIGURE;
EXEC sp_configure 'max worker threads', 0;
RECONFIGURE;
EXEC sp_configure 'lightweight pooling', 0;
RECONFIGURE;
EXEC sp_configure 'fill factor', 0;
RECONFIGURE;
EXEC sp_configure 'backup compression default', 1;
RECONFIGURE WITH OVERRIDE;

-- ==========================
-- Memory Configuration
-- ==========================
SELECT @MaximumMemory = ([total_physical_memory_kb] / 1024 * @MaxMem / 100)
FROM [master].[sys].[dm_os_sys_memory];

EXEC sp_configure 'min server memory', @MinMem;
RECONFIGURE;
EXEC sp_configure 'max server memory', @MaximumMemory;
RECONFIGURE;

-- ==========================
-- MAXDOP and Cost Threshold
-- ==========================
DECLARE 
    @logicalCPUs INT,
    @hyperthreadingRatio INT,
    @physicalCPU INT,
    @HTEnabled INT,
    @logicalCPUPerNuma INT,
    @NoOfNUMA INT;

SELECT 
    @logicalCPUs = cpu_count,
    @hyperthreadingRatio = hyperthread_ratio,
    @physicalCPU = cpu_count / hyperthread_ratio,
    @HTEnabled = CASE WHEN cpu_count > hyperthread_ratio THEN 1 ELSE 0 END
FROM sys.dm_os_sys_info;

SELECT TOP 1 @logicalCPUPerNuma = COUNT(*) 
FROM sys.dm_os_schedulers
WHERE [status] = 'VISIBLE ONLINE'
    AND parent_node_id < 64
GROUP BY parent_node_id;

SELECT @NoOfNUMA = COUNT(DISTINCT parent_node_id)
FROM sys.dm_os_schedulers
WHERE [status] = 'VISIBLE ONLINE'
    AND parent_node_id < 64;

-- Calculate MAXDOP Recommendation
IF (@logicalCPUs < 8 AND @HTEnabled = 0)
    SET @P_MAXDOP = @logicalCPUs;
ELSE IF (@logicalCPUs >= 8 AND @HTEnabled = 0)
    SET @P_MAXDOP = 8;
ELSE IF (@logicalCPUs >= 8 AND @HTEnabled = 1 AND @NoOfNUMA = 1)
    SET @P_MAXDOP = @logicalCPUPerNuma / @physicalCPU;
ELSE IF (@logicalCPUs >= 8 AND @HTEnabled = 1 AND @NoOfNUMA > 1)
    SET @P_MAXDOP = @logicalCPUPerNuma / @physicalCPU;

-- Apply MAXDOP and Cost Threshold
EXEC sp_configure 'max degree of parallelism', @P_MAXDOP;
RECONFIGURE;
EXEC sp_configure 'cost threshold for parallelism', @CostThreshold;
RECONFIGURE;

-- ==========================
-- Default Directories
-- ==========================
DECLARE @BackupDirectory NVARCHAR(500);
EXEC master..xp_instance_regread 
    @rootkey = 'HKEY_LOCAL_MACHINE',  
    @key = 'Software\Microsoft\MSSQLServer\MSSQLServer',  
    @value_name = 'BackupDirectory', 
    @BackupDirectory = @BackupDirectory OUTPUT;

SET @Backup = ISNULL(NULLIF(@Backup, ''), @BackupDirectory);
SET @DBfile = ISNULL(NULLIF(@DBfile, ''), CONVERT(NVARCHAR(500), SERVERPROPERTY('INSTANCEDEFAULTDATAPATH')));
SET @Logfile = ISNULL(NULLIF(@Logfile, ''), CONVERT(NVARCHAR(500), SERVERPROPERTY('INSTANCEDEFAULTLOGPATH')));

BEGIN TRY
    EXEC xp_instance_regwrite 
        N'HKEY_LOCAL_MACHINE', 
        N'Software\Microsoft\MSSQLServer\MSSQLServer', 
        N'DefaultData', 
        REG_SZ, 
        @DBfile;

    EXEC xp_instance_regwrite 
        N'HKEY_LOCAL_MACHINE', 
        N'Software\Microsoft\MSSQLServer\MSSQLServer', 
        N'DefaultLog', 
        REG_SZ, 
        @Logfile;

    EXEC xp_instance_regwrite 
        N'HKEY_LOCAL_MACHINE', 
        N'Software\Microsoft\MSSQLServer\MSSQLServer', 
        N'BackupDirectory', 
        REG_SZ, 
        @Backup;
END TRY
BEGIN CATCH
    PRINT 'Error setting registry values: ' + ERROR_MESSAGE();
END CATCH

-- ==========================
-- TempDB Files Configuration
-- ==========================
DECLARE 
    @cpu INT = (SELECT cpu_count FROM sys.dm_os_sys_info),
    @currentTempFiles INT = (SELECT COUNT(*) FROM tempdb.sys.database_files),
    @requiredTempFiles INT,
    @int INT = 1,
    @maxFile INT;

SET @requiredTempFiles = CASE WHEN @cpu < 8 THEN 5 ELSE 9 END;

IF @currentTempFiles = @requiredTempFiles
    PRINT 'TempDB Files Are OK';
ELSE IF @currentTempFiles > @requiredTempFiles
    PRINT CAST(@currentTempFiles - @requiredTempFiles AS NVARCHAR(100)) + ' files need to be removed';
ELSE
BEGIN
    SET @maxFile = @requiredTempFiles - @currentTempFiles;
    WHILE @int <= @maxFile
    BEGIN
        DECLARE @addfiles NVARCHAR(1000) = 
            'ALTER DATABASE [tempdb] ADD FILE (NAME = N''tempdb_' + CAST(@int AS NVARCHAR(10)) +
            ''', FILENAME = N''' + @TempfilePath + 'tempdb_' + CAST(@int AS NVARCHAR(10)) + 
            '.ndf'', SIZE = ' + @TempfileSize + ')';
        PRINT @addfiles;
        BEGIN TRY
            EXEC (@addfiles);
        END TRY
        BEGIN CATCH
            PRINT 'Error adding TempDB file: ' + ERROR_MESSAGE();
        END CATCH
        SET @int = @int + 1;
    END
END
GO
