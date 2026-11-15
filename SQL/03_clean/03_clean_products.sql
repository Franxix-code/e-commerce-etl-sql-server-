/* =====================================================================
   File     : 03_clean_products.sql
   Purpose  : Cleans stg.products and loads cln.products (rules BR-P01 to BR-P07). The unique SKU index lives in 00_create_clean_tables.sql.
   Needs    : staging loaded
   ===================================================================== */

CREATE OR ALTER PROCEDURE etl.usp_load_cln_products
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        -------------------------------------------------------------------------
        -- 1) CLEAN: every staged row goes into the temp table (nothing filtered)
        -------------------------------------------------------------------------
        DROP TABLE IF EXISTS #products_cleaned;

        SELECT
            CASE WHEN UPPER(TRIM(product_id)) IN ('', '-', 'NA', 'NULL', 'NONE', 'N/A') THEN NULL
                 WHEN UPPER(TRIM(product_id)) LIKE 'PROD[0-9]%' THEN 'PROD-' + SUBSTRING(UPPER(TRIM(product_id)), 5, 20)
                 ELSE UPPER(TRIM(product_id)) END AS product_id,

            CASE WHEN UPPER(TRIM(sku)) IN ('', '-', 'NA', 'NULL', 'NONE', 'N/A') THEN NULL
                 WHEN UPPER(TRIM(sku)) LIKE 'SKU[0-9]%' THEN 'SKU-' + SUBSTRING(UPPER(TRIM(sku)), 4, 20)
                 ELSE UPPER(TRIM(sku)) END AS sku,

            CASE WHEN UPPER(TRIM(product_name)) IN ('', '-', 'NA', 'NULL', 'NONE', 'N/A') THEN NULL
                 ELSE TRIM(product_name) END AS product_name,

            -- BR-P06
            CASE
                WHEN UPPER(TRIM(category)) LIKE '%ELECTRONIC%' THEN 'Electronics'
                WHEN UPPER(TRIM(category)) LIKE '%FASHION%'    THEN 'Fashion'
                WHEN UPPER(TRIM(category)) LIKE '%HOME%'       THEN 'Home and Kitchen'
                WHEN UPPER(TRIM(category)) LIKE '%BEAUTY%'     THEN 'Beauty'
                WHEN UPPER(TRIM(category)) LIKE '%GROCER%'     THEN 'Grocery'
                WHEN UPPER(TRIM(category)) LIKE '%SPORT%'      THEN 'Sport'
                WHEN UPPER(TRIM(category)) LIKE '%BOOK%'       THEN 'Books'
                WHEN UPPER(TRIM(category)) LIKE '%TOY%'        THEN 'Games'
                WHEN UPPER(TRIM(category)) LIKE '%AUTO%'       THEN 'Automotive'
                WHEN UPPER(TRIM(category)) LIKE '%HEALTH%'     THEN 'Health'
                ELSE NULL
            END AS category,

            -- the brand, or the first word of the product name when the brand is missing
            CASE
                WHEN UPPER(TRIM(brand)) NOT IN ('', '-', 'NA', 'NULL', 'NONE', 'N/A')
                    THEN TRIM(brand)
                WHEN UPPER(TRIM(product_name)) NOT IN ('', '-', 'NA', 'NULL', 'NONE', 'N/A')
                    THEN LEFT(TRIM(product_name), CHARINDEX(' ', TRIM(product_name) + ' ') - 1)
            END AS brand,

            TRY_CAST(NULLIF(TRIM(REPLACE(REPLACE(REPLACE(UPPER(unit_price), 'NGN', ''), 'N', ''), ',', '')), '') AS DECIMAL(18,2)) AS unit_price,
            TRY_CAST(NULLIF(TRIM(REPLACE(REPLACE(REPLACE(UPPER(cost_price), 'NGN', ''), 'N', ''), ',', '')), '') AS DECIMAL(18,2)) AS cost_price,

            -- BR-P05: 'out of stock' and negative numbers become 0, junk becomes NULL
            CASE
                WHEN UPPER(TRIM(stock_qty)) LIKE '%OUT%'                      THEN 0
                WHEN TRY_CAST(NULLIF(TRIM(stock_qty), '') AS INT) < 0         THEN 0
                ELSE TRY_CAST(NULLIF(TRIM(stock_qty), '') AS INT)
            END AS stock_qty,

            CASE
                WHEN TRIM(created_date) LIKE '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]%'           THEN TRY_CONVERT(DATE, LEFT(TRIM(created_date), 10), 23)   -- 2024-03-05 (time part dropped)
                WHEN TRIM(created_date) LIKE '[0-9][0-9][0-9][0-9]/[0-9][0-9]/[0-9][0-9]'            THEN TRY_CONVERT(DATE, REPLACE(TRIM(created_date), '/', '-'), 23)   -- 2024/03/05
                WHEN TRIM(created_date) LIKE '[0-9][0-9]/[0-9][0-9]/[0-9][0-9][0-9][0-9]'            THEN TRY_CONVERT(DATE, TRIM(created_date), 103)   -- 05/03/2024 (day first)
                WHEN TRIM(created_date) LIKE '[0-9][0-9].[0-9][0-9].[0-9][0-9][0-9][0-9]'            THEN TRY_CONVERT(DATE, TRIM(created_date), 104)   -- 05.03.2024 (day first)
                WHEN TRIM(created_date) LIKE '[0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9]'            THEN TRY_CONVERT(DATE, TRIM(created_date), 110)   -- 03-05-2024 (month first)
                WHEN TRIM(created_date) LIKE '[0-9][0-9]-[0-9][0-9]-[0-9][0-9]'                      THEN TRY_CONVERT(DATE, TRIM(created_date), 5)     -- 05-03-24 (day first)
                WHEN TRIM(created_date) LIKE '[0-9][0-9] [A-Za-z][A-Za-z][A-Za-z] [0-9][0-9][0-9][0-9]' THEN TRY_CONVERT(DATE, TRIM(created_date), 106) -- 05 Mar 2024
                WHEN TRIM(created_date) LIKE '[A-Za-z]%[0-9][0-9], [0-9][0-9][0-9][0-9]'             THEN TRY_CONVERT(DATE, TRIM(created_date), 107)   -- March 05, 2024
            END AS created_date,

            CASE
                WHEN UPPER(TRIM(status)) IN ('ACTIVE', 'A', '1')              THEN 'Active'
                WHEN UPPER(TRIM(status)) IN ('INACTIVE', 'I')                 THEN 'Inactive'
                WHEN UPPER(TRIM(status)) IN ('DISCONTINUED', 'DISC.')         THEN 'Discontinued'
                ELSE NULL
            END AS status,

            load_id,
            source_row_number,
            ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(product_id))
                               ORDER BY source_row_number) AS rn
        INTO #products_cleaned
        FROM stg.products;

        -------------------------------------------------------------------------
        -- 2) REJECTS: one reason per row, in priority order
        -------------------------------------------------------------------------
        ALTER TABLE #products_cleaned ADD reject_rule NVARCHAR(20) NULL, reject_reason NVARCHAR(200) NULL;

        -- BR-P01: duplicate product_id
        UPDATE #products_cleaned
        SET reject_rule = 'BR-P01', reject_reason = 'Duplicate product_id; first row in file was kept'
        WHERE rn > 1;

        -- BR-P03: the price must exist and be above 0
        UPDATE #products_cleaned
        SET reject_rule = 'BR-P03', reject_reason = 'unit_price missing or not greater than 0'
        WHERE reject_rule IS NULL AND (unit_price IS NULL OR unit_price <= 0);

        -------------------------------------------------------------------------
        -- 3) FIXES and FLAGS (only rows that were not rejected)
        -------------------------------------------------------------------------
        ALTER TABLE #products_cleaned ADD
            dq_sku_issue          NVARCHAR(20) NULL,
            dq_invalid_cost_price BIT NOT NULL DEFAULT 0,
            dq_stock_adjusted     BIT NOT NULL DEFAULT 0;

        -- BR-P04: cost must be above 0 and not higher than the price, otherwise NULL
        UPDATE #products_cleaned
        SET cost_price = NULL
        WHERE reject_rule IS NULL AND cost_price IS NOT NULL
          AND (cost_price <= 0 OR cost_price > unit_price);

        UPDATE p
        SET dq_invalid_cost_price = 1
        FROM #products_cleaned AS p
        JOIN stg.products AS s ON s.source_row_number = p.source_row_number
        WHERE p.reject_rule IS NULL AND p.cost_price IS NULL
          AND ISNULL(UPPER(TRIM(s.cost_price)), '') NOT IN ('', '-', 'NA', 'NULL', 'NONE', 'N/A');

        -- BR-P05: stock that was changed to 0 (negative number or 'out of stock')
        UPDATE p
        SET dq_stock_adjusted = 1
        FROM #products_cleaned AS p
        JOIN stg.products AS s ON s.source_row_number = p.source_row_number
        WHERE p.reject_rule IS NULL
          AND (UPPER(TRIM(s.stock_qty)) LIKE '%OUT%' OR TRY_CAST(NULLIF(TRIM(s.stock_qty), '') AS INT) < 0);

        -- BR-P02: SKU problems are flagged, never rejected
        UPDATE #products_cleaned
        SET dq_sku_issue = 'MISSING'
        WHERE reject_rule IS NULL AND sku IS NULL;

        UPDATE #products_cleaned
        SET dq_sku_issue = 'DUPLICATE'
        WHERE reject_rule IS NULL
          AND sku IN (SELECT sku FROM #products_cleaned
                      WHERE reject_rule IS NULL AND sku IS NOT NULL
                      GROUP BY sku HAVING COUNT(*) > 1);

        -------------------------------------------------------------------------
        -- 4) WRITE THE REJECTS
        -------------------------------------------------------------------------
        DELETE FROM err.rejected_rows WHERE table_name = 'products';

        INSERT INTO err.rejected_rows (load_id, table_name, source_row_number, record_key, rule_id, reason)
        SELECT load_id, 'products', source_row_number, product_id, reject_rule, reject_reason
        FROM #products_cleaned
        WHERE reject_rule IS NOT NULL;

        -------------------------------------------------------------------------
        -- 5) LOAD
        -------------------------------------------------------------------------
        DELETE FROM cln.products;

        INSERT INTO cln.products
            (product_id, sku, product_name, category, brand, unit_price, cost_price, stock_qty,
             created_date, status, dq_sku_issue, dq_invalid_cost_price, dq_stock_adjusted,
             load_id, source_row_number)
        SELECT
             product_id, sku, product_name, category, brand, unit_price, cost_price, stock_qty,
             created_date, status, dq_sku_issue, dq_invalid_cost_price, dq_stock_adjusted,
             load_id, source_row_number
        FROM #products_cleaned
        WHERE reject_rule IS NULL;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END;
GO
