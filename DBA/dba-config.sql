/*****************************************************************
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

-- Global Declarations
DECLARE @MinMem INT = COALESCE(NULLIF(@MinMem, ''), 0);
DECLARE @MaxMem INT = COALESCE(NULLIF(@MaxMem, ''), 90);
DECLARE @P_MAXDOP INT = COALESCE(NULLIF(@P_MAXDOP, ''), NULL);
DECLARE @CostThresHold INT = COALESCE(NULLIF(@CostThresHold, ''), 50);
DECLARE @DBfile NVARCHAR(500) = COALESCE(NULLIF(@DBfile, ''), (SELECT CONVERT(NVARCHAR(500), SERVERPROPERTY('INSTANCEDEFAULTDATAPATH'))));
DECLARE @Logfile NVARCHAR(500) = COALESCE(NULLIF(@Logfile, ''), (SELECT CONVERT(NVARCHAR(500), SERVERPROPERTY('INSTANCEDEFAULTLOGPATH'))));
DECLARE @Backup NVARCHAR(500) = COALESCE(NULLIF(@Backup, ''), NULL);
DECLARE @TempfilePath NVARCHAR(500) = COALESCE(NULLIF(@TempfilePath, ''), NULL);
DECLARE @TempfileSize NVARCHAR(100) = COALESCE(NULLIF(@TempfileSize, ''), '100MB');
DECLARE @MaximumMem INT;
DECLARE @hyperthreadingRatio BIT;
DECLARE @logicalCPUs INT;
DECLARE @HTEnabled INT;
DECLARE @physicalCPU INT;
DECLARE @logicalCPUPerNuma INT;
DECLARE @NoOfNUMA INT;
DECLARE @MaxDOP INT;

-- Show advanced options
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;

-- Configure settings
EXEC sp_configure 'index create memory', 0;
EXEC sp_configure 'min memory per query', 1024;
EXEC sp_configure 'priority boost', 0;
EXEC sp_configure 'max worker threads', 0;
EXEC sp_configure 'lightweight pooling', 0;
EXEC sp_configure 'fill factor', 0;
EXEC sp_configure 'backup compression default', 1;
RECONFIGURE WITH OVERRIDE;

-- Set Min/Max SQL Memory
SET @MaximumMem = (SELECT [total_physical_memory_kb] / 1024 * @MaxMem / 100 FROM [master].[sys].[dm_os_sys_memory]);
EXEC sp_configure 'min server memory', @MinMem;
EXEC sp_configure 'max server memory', @MaximumMem;

-- Set MAX DOP and Cost Threshold
SELECT 
    @logicalCPUs = cpu_count, 
    @hyperthreadingRatio = hyperthread_ratio,
    @physicalCPU = cpu_count / hyperthread_ratio,
    @HTEnabled = CASE WHEN cpu_count > hyperthread_ratio THEN 1 ELSE 0 END
FROM sys.dm_os_sys_info
OPTION (RECOMPILE);

SELECT 
    @logicalCPUPerNuma = COUNT(parent_node_id)
FROM sys.dm_os_schedulers
WHERE [status] = 'VISIBLE ONLINE' AND parent_node_id < 64
GROUP BY parent_node_id
OPTION (RECOMPILE);

SELECT 
    @NoOfNUMA = COUNT(DISTINCT parent_node_id)
FROM sys.dm_os_schedulers
WHERE [status] = 'VISIBLE ONLINE' AND parent_node_id < 64;

SET @P_MAXDOP = COALESCE(@P_MAXDOP, (
    CASE 
        WHEN @logicalCPUs < 8 AND @HTEnabled = 0 THEN @logicalCPUs
        WHEN @logicalCPUs >= 8 AND @HTEnabled = 0 THEN 8
        WHEN @logicalCPUs >= 8 AND @HTEnabled = 1 AND @NoOfNUMA = 1 THEN @logicalCPUPerNuma / @physicalCPU
        WHEN @logicalCPUs >= 8 AND @HTEnabled = 1 AND @NoOfNUMA > 1 THEN @logicalCPUPerNuma / @physicalCPU
        ELSE NULL
    END
));

EXEC sp_configure 'max degree of parallelism', @P_MAXDOP;
EXEC sp_configure 'cost threshold for parallelism', @CostThresHold;

-- Set Default Directories for Data/Log/Backup
DECLARE @BackupDirectory NVARCHAR(100);
EXEC master..xp_instance_regread 
    @rootkey = 'HKEY_LOCAL_MACHINE',  
    @key = 'Software\Microsoft\MSSQLServer\MSSQLServer',  
    @value_name = 'BackupDirectory', 
    @BackupDirectory = @BackupDirectory OUTPUT;

SET @Backup = COALESCE(@Backup, @BackupDirectory);
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

-- Add TempDB Files
DECLARE @cpu INT = (SELECT COUNT(cpu_count) FROM sys.dm_os_sys_info);
DECLARE @currentTempFiles INT = (SELECT COUNT(name) FROM tempdb.sys.database_files);
DECLARE @requiredTempFiles INT;

SET @requiredTempFiles = CASE 
    WHEN @cpu < 8 THEN 5
    ELSE 9
END;

IF @currentTempFiles < @requiredTempFiles
BEGIN
    DECLARE @int INT = 1;
    DECLARE @MAX_File INT = @requiredTempFiles - @currentTempFiles;

    WHILE @int <= @MAX_File
    BEGIN
        DECLARE @addFiles NVARCHAR(500) = 
            'ALTER DATABASE [tempdb] ADD FILE (NAME = ''tempdb_' + CAST(@int AS NVARCHAR(10)) + ''', FILENAME = ''' + @TempfilePath + 'tempdb_' + CAST(@int AS NVARCHAR(10)) + '.ndf'', SIZE = ' + @TempfileSize + ')';
        
        EXEC (@addFiles);
        SET @int = @int + 1;
    END;

    PRINT CAST(@currentTempFiles - @requiredTempFiles AS NVARCHAR(100)) + ' File(s) need to be removed';
END
ELSE
BEGIN
    PRINT 'TempDB Files Are OK';
END
GO
