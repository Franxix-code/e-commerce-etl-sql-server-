/* =====================================================================
   File     : 01_create_database_and_schemas.sql
   Purpose  : Creates the ecommerce database and the five schemas (stg, cln, err, rpt, etl).
   WARNING  : drops the existing ecommerce database. Run only on a development machine.
   ===================================================================== */

USE master;
GO

IF DB_ID('ecommerce') IS NOT NULL
BEGIN
    ALTER DATABASE ecommerce SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE ecommerce;
END
GO

CREATE DATABASE ecommerce;
GO

USE ecommerce;
GO

IF SCHEMA_ID('stg') IS NULL EXEC('CREATE SCHEMA stg');   -- raw staging copy of the CSV files
IF SCHEMA_ID('cln') IS NULL EXEC('CREATE SCHEMA cln');   -- clean, typed, keyed tables
IF SCHEMA_ID('err') IS NULL EXEC('CREATE SCHEMA err');   -- rejected rows
IF SCHEMA_ID('rpt') IS NULL EXEC('CREATE SCHEMA rpt');   -- reporting (KPI) tables
IF SCHEMA_ID('etl') IS NULL EXEC('CREATE SCHEMA etl');   -- control tables and procedures
GO
