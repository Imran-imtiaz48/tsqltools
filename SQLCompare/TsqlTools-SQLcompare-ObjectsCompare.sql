/*****************************************************************
                 ----------------------- 
                 tsqltools - SQLCOMPARE - Objects Compare
                 -----------------------
Version: v1.0 
Release Date: 2017-07-30
Author: Bhuvanesh(@SQLadmin)
Feedback: mailto:r.bhuvanesh@outlook.com
Updates: http://medium.com/sqladmin
Repo: https://github.com/SqlAdmin/tsqltools/
License: 
  tsqltools is free to download.It contains Tsql stored procedures 
  and scripts to help the DBAs and Developers to make their job easier
(C) 2017
 
 
======================================================================

What is TsqlTools-SQLcompare? 

TsqlTools-SQLcompare is a tsqlscript that will help to compare Databases, 
Tables, Objects, Indexices between two servers without any tools.

======================================================================
How to Start?

Use a centalized server  and create LinkedServers from the centralized server.
Or Create LinkedServer on SourceDB server then run this query on SourceDB server.

========================================================================*/
-- =============================================
-- Author:      [Your Name]
-- Description: Compare objects between two SQL Server instances
-- =============================================

DECLARE @SOURCEDBSERVER VARCHAR(100) = '[db01]'  -- Replace with your source DB server name
DECLARE @DESTINATIONDBSERVER VARCHAR(100) = '[db02]'  -- Replace with your target DB server name

DECLARE @SOURCE_SQL_DBNAME NVARCHAR(MAX)
DECLARE @SOURCE_DATABASENAME TABLE (dbname VARCHAR(100))

-- Get list of user databases (database_id > 4 excludes system dbs)
SET @SOURCE_SQL_DBNAME = 'SELECT name FROM ' + QUOTENAME(@SOURCEDBSERVER) + '.master.sys.databases WHERE database_id > 4'

INSERT INTO @SOURCE_DATABASENAME
EXEC sp_executesql @SOURCE_SQL_DBNAME

-- Temporary table for results
CREATE TABLE #objectstatus (
    dbname       NVARCHAR(500),
    objectname   NVARCHAR(500),
    objecttype   VARCHAR(500),
    status       NVARCHAR(500)
)

DECLARE db_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT dbname FROM @SOURCE_DATABASENAME

DECLARE @SOURCE_DBNAME VARCHAR(100)
OPEN db_cursor

FETCH NEXT FROM db_cursor INTO @SOURCE_DBNAME

BEGIN TRY
    WHILE @@FETCH_STATUS = 0
    BEGIN
        DECLARE @SOURCEDBNAMEFULL NVARCHAR(300) = QUOTENAME(@SOURCEDBSERVER) + '.' + QUOTENAME(@SOURCE_DBNAME)
        DECLARE @DESTDBNAMEFULL   NVARCHAR(300) = QUOTENAME(@DESTINATIONDBSERVER) + '.' + QUOTENAME(@SOURCE_DBNAME)
        DECLARE @SQL NVARCHAR(MAX)

        SET @SQL = N'
            SELECT 
                ''' + @SOURCE_DBNAME + ''' AS dbname,
                ISNULL(SoSource.name, SoDestination.name) AS objectname,
                ISNULL(SoSource.type_desc, SoDestination.type_desc) AS objecttype,
                CASE
                    WHEN SoSource.object_id IS NULL THEN ''Available on ' + @DESTDBNAMEFULL + '''
                    WHEN SoDestination.object_id IS NULL THEN ''Available on ' + @SOURCEDBNAMEFULL + '''
                    ELSE ''Available On Both Servers''
                END AS status
            FROM (
                SELECT * FROM ' + @SOURCEDBNAMEFULL + '.sys.objects 
                WHERE type_desc NOT IN (''INTERNAL_TABLE'',''SYSTEM_TABLE'',''SERVICE_QUEUE'')
            ) SoSource
            FULL OUTER JOIN (
                SELECT * FROM ' + @DESTDBNAMEFULL + '.sys.objects
                WHERE type_desc NOT IN (''INTERNAL_TABLE'',''SYSTEM_TABLE'',''SERVICE_QUEUE'')
            ) SoDestination
                ON SoSource.name = SoDestination.name COLLATE database_default
                AND SoSource.type = SoDestination.type COLLATE database_default
            ORDER BY ISNULL(SoSource.type, SoDestination.type)
        '

        INSERT INTO #objectstatus (dbname, objectname, objecttype, status)
        EXEC sp_executesql @SQL

        FETCH NEXT FROM db_cursor INTO @SOURCE_DBNAME
    END
END TRY
BEGIN CATCH
    PRINT 'Error: ' + ERROR_MESSAGE()
END CATCH

CLOSE db_cursor
DEALLOCATE db_cursor

-- Example: Show all object types. Adjust WHERE as needed.
SELECT * FROM #objectstatus WHERE objecttype = 'USER_TABLE' ORDER BY dbname, objectname
SELECT * FROM #objectstatus WHERE objecttype = 'CHECK_CONSTRAINT' ORDER BY dbname, objectname
SELECT * FROM #objectstatus WHERE objecttype = 'DEFAULT_CONSTRAINT' ORDER BY dbname, objectname
SELECT * FROM #objectstatus WHERE objecttype = 'FOREIGN_KEY_CONSTRAINT' ORDER BY dbname, objectname
SELECT * FROM #objectstatus WHERE objecttype = 'PRIMARY_KEY_CONSTRAINT' ORDER BY dbname, objectname
SELECT * FROM #objectstatus WHERE objecttype = 'UNIQUE_CONSTRAINT' ORDER BY dbname, objectname
SELECT * FROM #objectstatus WHERE objecttype = 'SQL_TRIGGER' ORDER BY dbname, objectname
SELECT * FROM #objectstatus WHERE objecttype = 'VIEW' ORDER BY dbname, objectname
SELECT * FROM #objectstatus WHERE objecttype = 'SQL_STORED_PROCEDURE' ORDER BY dbname, objectname

-- Select all other object types
SELECT * FROM #objectstatus
WHERE objecttype NOT IN (
    'USER_TABLE', 'CHECK_CONSTRAINT', 'DEFAULT_CONSTRAINT',
    'FOREIGN_KEY_CONSTRAINT', 'PRIMARY_KEY_CONSTRAINT',
    'SQL_TRIGGER', 'VIEW', 'SQL_STORED_PROCEDURE', 'UNIQUE_CONSTRAINT'
)
ORDER BY dbname, objectname

DROP TABLE IF EXISTS #objectstatus
 



 

  
