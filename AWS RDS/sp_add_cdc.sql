/*****************************************************************
                 -------------------------------------
                 tsqltools - RDS Add CDC
                 -------------------------------------
Description: This stored procedure will help you to enable CDC on 
all the exsiting tables. You have to run this store procedure on the 
database where you need to add the tables. It won't support Cross 
database's tables.

How to Run: If you want to enable CDC on the tables which 
all are in DBAdmin database,

USE DBAdmin
GO
EXEC sp_add_cdc 'DBAdmin'

-------------------------------------------------------------------

Version: v1.0 
Release Date: 2018-02-09
Author: Bhuvanesh(@SQLadmin)
Feedback: mailto:r.bhuvanesh@outlook.com
Updates: https://github.com/SqlAdmin/tsqltools/
Blog: http://www.sqlgossip.com/automatically-enable-cdc-in-rds-sql-server/
License: GPL-3.0
  tsqltools is free to download.It contains Tsql stored procedures 
  and scripts to help the DBAs and Developers to make job easier
(C) 2017
*******************************************************************/  

-- READ THE DESCRIPTION BEFORE EXECUTE THIS ***
IF OBJECT_ID('dbo.sp_add_cdc') IS NULL
    EXEC ('CREATE PROCEDURE dbo.sp_add_cdc AS RETURN 0;');
GO

ALTER PROCEDURE [dbo].[sp_add_cdc]
    @cdcdbname NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        -- Enable CDC at the database level
        EXEC msdb.dbo.rds_cdc_enable_db @cdcdbname;

        -- Cursor for Primary Key tables not already tracked by CDC
        DECLARE @pk_schema NVARCHAR(100), @pk_table NVARCHAR(100);
        DECLARE primary_tbl_cursor CURSOR FOR
            SELECT t1.table_schema, t1.table_name
            FROM INFORMATION_SCHEMA.TABLES AS t1
            INNER JOIN INFORMATION_SCHEMA.TABLE_CONSTRAINTS AS t2
                ON t1.TABLE_NAME = t2.TABLE_NAME AND t1.table_schema = t2.table_schema
            INNER JOIN sys.tables AS t3
                ON t1.table_name = t3.name
            WHERE t1.TABLE_TYPE = 'BASE TABLE'
              AND t2.CONSTRAINT_TYPE = 'PRIMARY KEY'
              AND t1.table_schema != 'cdc'
              AND t3.is_tracked_by_cdc = 0;

        OPEN primary_tbl_cursor;
        FETCH NEXT FROM primary_tbl_cursor INTO @pk_schema, @pk_table;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            EXEC sys.sp_cdc_enable_table
                @source_schema = @pk_schema,
                @source_name = @pk_table,
                @role_name = NULL,
                @supports_net_changes = 1;

            FETCH NEXT FROM primary_tbl_cursor INTO @pk_schema, @pk_table;
        END
        CLOSE primary_tbl_cursor;
        DEALLOCATE primary_tbl_cursor;

        -- Cursor for tables without Primary Key and not tracked by CDC
        DECLARE @np_schema NVARCHAR(100), @np_table NVARCHAR(100);
        DECLARE nonprimary_cursor CURSOR FOR
            SELECT t1.table_schema, t1.table_name
            FROM INFORMATION_SCHEMA.TABLES AS t1
            INNER JOIN sys.tables AS t3
                ON t1.table_name = t3.name
            WHERE t1.TABLE_TYPE = 'BASE TABLE'
              AND t1.table_schema != 'cdc'
              AND t3.is_tracked_by_cdc = 0
              AND t1.table_name != 'systranschemas'
              AND NOT EXISTS (
                    SELECT 1
                    FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS AS t2
                    WHERE t2.table_name = t1.table_name
                    AND t2.table_schema = t1.table_schema
                    AND t2.CONSTRAINT_TYPE = 'PRIMARY KEY'
              );

        OPEN nonprimary_cursor;
        FETCH NEXT FROM nonprimary_cursor INTO @np_schema, @np_table;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            EXEC sys.sp_cdc_enable_table
                @source_schema = @np_schema,
                @source_name = @np_table,
                @role_name = NULL,
                @supports_net_changes = 0;

            FETCH NEXT FROM nonprimary_cursor INTO @np_schema, @np_table;
        END
        CLOSE nonprimary_cursor;
        DEALLOCATE nonprimary_cursor;
    END TRY
    BEGIN CATCH
        -- Clean up cursors if error occurs
        IF CURSOR_STATUS('global', 'primary_tbl_cursor') >= -1
        BEGIN
            CLOSE primary_tbl_cursor;
            DEALLOCATE primary_tbl_cursor;
        END
        IF CURSOR_STATUS('global', 'nonprimary_cursor') >= -1
        BEGIN
            CLOSE nonprimary_cursor;
            DEALLOCATE nonprimary_cursor;
        END

        -- Rethrow error
        THROW;
    END CATCH
END
GO
