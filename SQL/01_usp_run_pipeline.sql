/* =====================================================================
   File     : 01_usp_run_pipeline.sql
   Purpose  : Master procedure: runs the whole pipeline (staging, clean layer, reporting) with one call.
   Usage    : EXEC etl.usp_run_pipeline @data_folder = N'C:\path\to\csv\files\';
   Order    : clean tables are cleared children first, loaded parents first (foreign keys decide the order)
   ===================================================================== */

CREATE OR ALTER PROCEDURE etl.usp_run_pipeline
    @data_folder NVARCHAR(400) = N'C:\data\messy_ecommerce\'
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @start DATETIME2 = SYSDATETIME();

    -- 1. stage the CSV files
    EXEC etl.usp_load_stg_all @data_folder = @data_folder;

    -- 2. clear the clean tables, children before parents
    DELETE FROM cln.returns;           DELETE FROM cln.support_tickets;
    DELETE FROM cln.reviews;           DELETE FROM cln.shipments;
    DELETE FROM cln.payments;          DELETE FROM cln.order_items;
    DELETE FROM cln.orders;            DELETE FROM cln.addresses;
    DELETE FROM cln.customers;         DELETE FROM cln.products;

    -- 3. load the clean tables, parents before children
    EXEC etl.usp_load_cln_customers;
    EXEC etl.usp_load_cln_products;
    EXEC etl.usp_load_cln_addresses;
    EXEC etl.usp_load_cln_orders;
    EXEC etl.usp_load_cln_order_items;
    EXEC etl.usp_update_cln_order_totals;      -- BR-O05 and BR-O07, needs the order items
    EXEC etl.usp_load_cln_payments;            -- BR-Y06 needs the order totals
    EXEC etl.usp_load_cln_shipments;
    EXEC etl.usp_load_cln_reviews;
    EXEC etl.usp_load_cln_returns;
    EXEC etl.usp_load_cln_support_tickets;

    -- 4. reporting tables and business KPIs
    EXEC etl.usp_build_rpt;

    PRINT CONCAT('PIPELINE COMPLETED in ', DATEDIFF(SECOND, @start, SYSDATETIME()), ' seconds');
END;
GO
