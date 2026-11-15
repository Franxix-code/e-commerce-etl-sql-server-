/* =====================================================================
   File     : 02_create_control_tables.sql
   Purpose  : Control tables: etl.run_log, etl.load_file_log and err.rejected_rows.
   Needs    : 01_create_database_and_schemas.sql
   ===================================================================== */

-- Run log: one row per pipeline run (the load_id stamped on every staged and clean row)
IF OBJECT_ID('etl.run_log', 'U') IS NOT NULL
    DROP TABLE etl.run_log;
CREATE TABLE etl.run_log (
    load_id    INT IDENTITY(1, 1) PRIMARY KEY,
    started_at DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    ended_at   DATETIME2 NULL,
    status     NVARCHAR(50) NULL            -- Running / Success / Mismatch / Failed
);
GO

-- Per-file load log: expected rows against loaded rows for each CSV file
IF OBJECT_ID('etl.load_file_log', 'U') IS NOT NULL
    DROP TABLE etl.load_file_log;
CREATE TABLE etl.load_file_log (
    log_id        INT IDENTITY(1, 1) PRIMARY KEY,
    load_id       INT NOT NULL,
    table_name    NVARCHAR(50)  NOT NULL,
    source_file   NVARCHAR(200) NOT NULL,
    expected_rows INT NULL,
    rows_loaded   INT NULL,
    status        NVARCHAR(50)  NOT NULL,   -- OK / MISMATCH
    error_message NVARCHAR(2000) NULL,
    logged_at     DATETIME2 NOT NULL DEFAULT SYSDATETIME()
);
GO

-- Rejected rows: every row removed from the pipeline, with the rule that rejected it
IF OBJECT_ID('err.rejected_rows', 'U') IS NOT NULL
    DROP TABLE err.rejected_rows;
CREATE TABLE err.rejected_rows (
    rejected_id       INT IDENTITY(1, 1) PRIMARY KEY,
    load_id           INT NOT NULL,
    table_name        NVARCHAR(50)  NOT NULL,
    source_row_number INT NOT NULL,           -- line number in the staged table / CSV file
    record_key        NVARCHAR(50)  NULL,     -- the row's primary key
    rule_id           NVARCHAR(50)  NULL,     -- business rule, e.g. BR-C01
    reason            NVARCHAR(500) NULL,
    rejected_at       DATETIME2 NOT NULL DEFAULT SYSDATETIME()
);
GO
