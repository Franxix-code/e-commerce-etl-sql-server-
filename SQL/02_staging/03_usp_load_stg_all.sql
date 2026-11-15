/* =====================================================================
   File     : 03_usp_load_stg_all.sql
   Purpose  : Loads the 10 CSV files into the staging tables in one run (one load_id).
   Params   : @data_folder  folder that holds the CSV files (must be readable by the SQL Server service)
   Steps    : for each file: TRUNCATE, BULK INSERT through the load view, stamp load_id and source_file, count rows
   Logs     : etl.run_log (the run) and etl.load_file_log (expected rows against loaded rows per file)
   ===================================================================== */

CREATE OR ALTER PROCEDURE etl.usp_load_stg_all
    @data_folder NVARCHAR(400) = N'C:\data\messy_ecommerce\'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @load_id     INT,
            @batch_start DATETIME2 = SYSDATETIME(),
            @table_start DATETIME2,
            @table_name  SYSNAME,
            @file_name   NVARCHAR(260),
            @expected    INT,
            @rows        INT,
            @sql         NVARCHAR(MAX),
            @i           INT = 1,
            @n           INT;

    IF RIGHT(@data_folder, 1) NOT IN (N'\', N'/') SET @data_folder += N'\';

    -- the files and the number of data rows each one must contain
    DECLARE @files TABLE (seq INT IDENTITY(1, 1), table_name SYSNAME, expected_rows INT);
    INSERT INTO @files (table_name, expected_rows) VALUES
        ('customers', 123600), ('addresses', 151500), ('products', 102000), ('orders', 202000),
        ('order_items', 388294), ('payments', 205579), ('shipments', 163609), ('reviews', 151500),
        ('returns', 111100), ('support_tickets', 111100);
    SELECT @n = COUNT(*) FROM @files;

    BEGIN TRY
        -- start the run
        INSERT INTO etl.run_log (status) VALUES ('Running');
        SET @load_id = SCOPE_IDENTITY();

        PRINT '===================================================';
        PRINT CONCAT('LOADING STG LAYER (load_id = ', @load_id, ')');
        PRINT '===================================================';

        WHILE @i <= @n
        BEGIN
            SELECT @table_name = table_name, @expected = expected_rows FROM @files WHERE seq = @i;
            SET @file_name  = @table_name + N'.csv';
            SET @table_start = SYSDATETIME();
            PRINT CONCAT('Loading ', @file_name, '...');

            -- 1) empty the staging table (also resets the IDENTITY, so source_row_number follows the file order)
            SET @sql = N'TRUNCATE TABLE stg.' + QUOTENAME(@table_name) + N';';
            EXEC (@sql);

            -- 2) load the CSV through the view (the file path cannot be a variable, so the statement is built as text)
            SET @sql = N'BULK INSERT stg.' + QUOTENAME(N'v_' + @table_name + N'_load')
                     + N' FROM ''' + REPLACE(@data_folder + @file_name, N'''', N'''''') + N''''
                     + N' WITH (FORMAT = ''CSV'', FIRSTROW = 2, FIELDTERMINATOR = '','', ROWTERMINATOR = ''0x0a'');';
            EXEC (@sql);

            -- 3) stamp the tracking columns on the rows just loaded
            SET @sql = N'UPDATE stg.' + QUOTENAME(@table_name)
                     + N' SET load_id = @p_load_id, source_file = @p_file WHERE load_id IS NULL;';
            EXEC sp_executesql @sql, N'@p_load_id INT, @p_file NVARCHAR(260)',
                 @p_load_id = @load_id, @p_file = @file_name;

            -- 4) count what landed and log it against the expected number
            SET @sql = N'SELECT @p_rows = COUNT(*) FROM stg.' + QUOTENAME(@table_name) + N';';
            EXEC sp_executesql @sql, N'@p_rows INT OUTPUT', @p_rows = @rows OUTPUT;

            INSERT INTO etl.load_file_log (load_id, table_name, source_file, expected_rows, rows_loaded, status)
            VALUES (@load_id, @table_name, @file_name, @expected, @rows,
                    CASE WHEN @rows = @expected THEN N'OK' ELSE N'MISMATCH' END);

            PRINT CONCAT('>>>>> ', FORMAT(@rows, 'N0'), ' rows in ',
                         DATEDIFF(SECOND, @table_start, SYSDATETIME()), ' seconds');
            SET @i += 1;
        END;

        -- close the run
        UPDATE etl.run_log
        SET status   = CASE WHEN EXISTS (SELECT 1 FROM etl.load_file_log
                                         WHERE load_id = @load_id AND status <> N'OK')
                            THEN 'Mismatch' ELSE 'Success' END,
            ended_at = SYSDATETIME()
        WHERE load_id = @load_id;

        PRINT '===================================================';
        PRINT 'LOADING STG LAYER COMPLETED';
        PRINT CONCAT('>>>>> Total load duration: ', DATEDIFF(SECOND, @batch_start, SYSDATETIME()), ' seconds');
        PRINT '===================================================';

        -- result: expected rows against loaded rows (diff must be 0 for every file)
        SELECT table_name, expected_rows, rows_loaded, rows_loaded - expected_rows AS diff, status
        FROM etl.load_file_log
        WHERE load_id = @load_id
        ORDER BY log_id;
    END TRY
    BEGIN CATCH
        UPDATE etl.run_log
        SET status = 'Failed', ended_at = SYSDATETIME()
        WHERE load_id = @load_id;

        PRINT CONCAT('ERROR: ', ERROR_MESSAGE());
        PRINT CONCAT('NUMBER: ', ERROR_NUMBER());
        PRINT CONCAT('LINE: ', ERROR_LINE());
        THROW;
    END CATCH
END;
GO
