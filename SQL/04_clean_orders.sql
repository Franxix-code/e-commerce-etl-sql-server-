/* =====================================================================
   File     : 04_clean_orders.sql
   Purpose  : Cleans stg.orders and loads cln.orders (rules BR-O01 to BR-O04, BR-O06, BR-O08). The totals rules BR-O05 and BR-O07 run in 05_update_order_totals.sql.
   Needs    : cln.customers and cln.addresses loaded (foreign keys)
   ===================================================================== */

CREATE OR ALTER PROCEDURE etl.usp_load_cln_orders
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        -------------------------------------------------------------------------
        -- 1) CLEAN: every staged row goes into the temp table (nothing filtered)
        -------------------------------------------------------------------------
        DROP TABLE IF EXISTS #orders_cleaned;

        SELECT
            CASE WHEN UPPER(TRIM(order_id)) IN ('', '-', 'NA', 'NULL', 'NONE', 'N/A') THEN NULL
                 WHEN UPPER(TRIM(order_id)) LIKE 'ORD[0-9]%' THEN 'ORD-' + SUBSTRING(UPPER(TRIM(order_id)), 4, 20)
                 ELSE UPPER(TRIM(order_id)) END AS order_id,
            CASE WHEN UPPER(TRIM(customer_id)) IN ('', '-', 'NA', 'NULL', 'NONE', 'N/A') THEN NULL
                 WHEN UPPER(TRIM(customer_id)) LIKE 'CUST[0-9]%' THEN 'CUST-' + SUBSTRING(UPPER(TRIM(customer_id)), 5, 20)
                 ELSE UPPER(TRIM(customer_id)) END AS customer_id,
            CASE WHEN UPPER(TRIM(shipping_address_id)) IN ('', '-', 'NA', 'NULL', 'NONE', 'N/A') THEN NULL
                 WHEN UPPER(TRIM(shipping_address_id)) LIKE 'ADDR[0-9]%' THEN 'ADDR-' + SUBSTRING(UPPER(TRIM(shipping_address_id)), 5, 20)
                 ELSE UPPER(TRIM(shipping_address_id)) END AS shipping_address_id,

            CASE
                WHEN TRIM(order_date) LIKE '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]%'           THEN TRY_CONVERT(DATE, LEFT(TRIM(order_date), 10), 23)   -- 2024-03-05 (time part dropped)
                WHEN TRIM(order_date) LIKE '[0-9][0-9][0-9][0-9]/[0-9][0-9]/[0-9][0-9]'            THEN TRY_CONVERT(DATE, REPLACE(TRIM(order_date), '/', '-'), 23)   -- 2024/03/05
                WHEN TRIM(order_date) LIKE '[0-9][0-9]/[0-9][0-9]/[0-9][0-9][0-9][0-9]'            THEN TRY_CONVERT(DATE, TRIM(order_date), 103)   -- 05/03/2024 (day first)
                WHEN TRIM(order_date) LIKE '[0-9][0-9].[0-9][0-9].[0-9][0-9][0-9][0-9]'            THEN TRY_CONVERT(DATE, TRIM(order_date), 104)   -- 05.03.2024 (day first)
                WHEN TRIM(order_date) LIKE '[0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9]'            THEN TRY_CONVERT(DATE, TRIM(order_date), 110)   -- 03-05-2024 (month first)
                WHEN TRIM(order_date) LIKE '[0-9][0-9]-[0-9][0-9]-[0-9][0-9]'                      THEN TRY_CONVERT(DATE, TRIM(order_date), 5)     -- 05-03-24 (day first)
                WHEN TRIM(order_date) LIKE '[0-9][0-9] [A-Za-z][A-Za-z][A-Za-z] [0-9][0-9][0-9][0-9]' THEN TRY_CONVERT(DATE, TRIM(order_date), 106) -- 05 Mar 2024
                WHEN TRIM(order_date) LIKE '[A-Za-z]%[0-9][0-9], [0-9][0-9][0-9][0-9]'             THEN TRY_CONVERT(DATE, TRIM(order_date), 107)   -- March 05, 2024
            END AS order_date,

            -- BR-O04
            CASE
                WHEN UPPER(TRIM(order_status)) IN ('DELIVERED', 'COMPLETE', 'COMPLETED') THEN 'Delivered'
                WHEN UPPER(TRIM(order_status)) IN ('SHIPPED', 'IN TRANSIT')              THEN 'Shipped'
                WHEN UPPER(TRIM(order_status)) = 'PROCESSING'                            THEN 'Processing'
                WHEN UPPER(TRIM(order_status)) IN ('CANCELLED', 'CANCELED')              THEN 'Cancelled'
                WHEN UPPER(TRIM(order_status)) = 'RETURNED'                              THEN 'Returned'
                WHEN UPPER(TRIM(order_status)) = 'PENDING'                               THEN 'Pending'
                WHEN UPPER(TRIM(order_status)) = 'FAILED'                                THEN 'Failed'
                ELSE NULL
            END AS order_status,

            CASE
                WHEN UPPER(TRIM(channel)) IN ('WEB', 'WEBSITE')                  THEN 'Web'
                WHEN UPPER(TRIM(channel)) IN ('MOBILE APP', 'MOBILE', 'APP')     THEN 'Mobile App'
                WHEN UPPER(TRIM(channel)) IN ('MARKETPLACE', 'MKT')              THEN 'Marketplace'
                WHEN UPPER(TRIM(channel)) IN ('CALL CENTER', 'PHONE ORDER')      THEN 'Call Center'
                ELSE NULL
            END AS channel,

            -- BR-O06
            CASE WHEN UPPER(TRIM(currency)) IN ('NGN', 'NAIRA', 'N') THEN 'NGN' END AS currency,

            CASE WHEN UPPER(TRIM(discount_code)) IN ('', '-', 'NA', 'NULL', 'NONE', 'N/A') THEN NULL
                 ELSE UPPER(TRIM(discount_code)) END AS discount_code,

            TRY_CAST(NULLIF(TRIM(REPLACE(REPLACE(REPLACE(UPPER(total_amount), 'NGN', ''), 'N', ''), ',', '')), '') AS DECIMAL(18,2)) AS total_amount,

            load_id,
            source_row_number,
            ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(order_id))
                               ORDER BY source_row_number) AS rn
        INTO #orders_cleaned
        FROM stg.orders;

        CREATE INDEX ix_ord_customer ON #orders_cleaned (customer_id);

        -------------------------------------------------------------------------
        -- 2) REJECTS: one reason per row, in priority order
        -------------------------------------------------------------------------
        ALTER TABLE #orders_cleaned ADD reject_rule NVARCHAR(20) NULL, reject_reason NVARCHAR(200) NULL;

        -- BR-O08: duplicate order_id
        UPDATE #orders_cleaned
        SET reject_rule = 'BR-O08', reject_reason = 'Duplicate order_id; first row in file was kept'
        WHERE rn > 1;

        -- BR-O01: the customer must exist
        UPDATE o
        SET reject_rule = 'BR-O01', reject_reason = 'customer_id not found in cln.customers'
        FROM #orders_cleaned AS o
        WHERE o.reject_rule IS NULL
          AND NOT EXISTS (SELECT 1 FROM cln.customers AS c WHERE c.customer_id = o.customer_id);

        -- BR-O02: the order date must be valid and not in the future
        UPDATE #orders_cleaned
        SET reject_rule = 'BR-O02', reject_reason = 'order_date missing, invalid or in the future'
        WHERE reject_rule IS NULL
          AND (order_date IS NULL OR order_date > CAST(GETDATE() AS DATE));

        -------------------------------------------------------------------------
        -- 3) FIXES and FLAGS (only rows that were not rejected)
        -------------------------------------------------------------------------
        ALTER TABLE #orders_cleaned ADD
            dq_address_issue       BIT NOT NULL DEFAULT 0,
            dq_order_before_signup BIT NOT NULL DEFAULT 0;

        -- BR-O03: the shipping address must exist and belong to the same customer, otherwise NULL
        UPDATE o
        SET shipping_address_id = NULL, dq_address_issue = 1
        FROM #orders_cleaned AS o
        WHERE o.reject_rule IS NULL
          AND o.shipping_address_id IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM cln.addresses AS a
                          WHERE a.address_id = o.shipping_address_id
                            AND a.customer_id = o.customer_id);

        -- BR-O02: an order dated before the customer signed up is flagged, not rejected
        UPDATE o
        SET dq_order_before_signup = 1
        FROM #orders_cleaned AS o
        JOIN cln.customers AS c ON c.customer_id = o.customer_id
        WHERE o.reject_rule IS NULL AND o.order_date < c.signup_date;

        -------------------------------------------------------------------------
        -- 4) WRITE THE REJECTS
        -------------------------------------------------------------------------
        DELETE FROM err.rejected_rows WHERE table_name = 'orders';

        INSERT INTO err.rejected_rows (load_id, table_name, source_row_number, record_key, rule_id, reason)
        SELECT load_id, 'orders', source_row_number, order_id, reject_rule, reject_reason
        FROM #orders_cleaned
        WHERE reject_rule IS NOT NULL;

        -------------------------------------------------------------------------
        -- 5) LOAD
        --    total_amount_calc, dq_total_mismatch and dq_no_items stay NULL here.
        --    They are filled by etl.usp_update_cln_order_totals after order_items is loaded.
        -------------------------------------------------------------------------
        DELETE FROM cln.orders;

        INSERT INTO cln.orders
            (order_id, customer_id, shipping_address_id, order_date, order_status, channel, currency,
             discount_code, total_amount, dq_address_issue, dq_order_before_signup, load_id, source_row_number)
        SELECT
             order_id, customer_id, shipping_address_id, order_date, order_status, channel, currency,
             discount_code, total_amount, dq_address_issue, dq_order_before_signup, load_id, source_row_number
        FROM #orders_cleaned
        WHERE reject_rule IS NULL;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END;
GO
