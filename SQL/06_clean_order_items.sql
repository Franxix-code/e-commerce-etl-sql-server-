/* =====================================================================
   File     : 06_clean_order_items.sql
   Purpose  : Cleans stg.order_items and loads cln.order_items (rules BR-I01 to BR-I06).
   Needs    : cln.orders and cln.products loaded (foreign keys)
   ===================================================================== */

CREATE OR ALTER PROCEDURE etl.usp_load_cln_order_items
AS
BEGIN 
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	BEGIN TRY
		BEGIN TRAN;
			DROP TABLE IF EXISTS #order_items_cleaned;
			SELECT 
				CASE
					WHEN UPPER(TRIM(order_item_id)) IN ('', '-', 'NA', 'NULL', 'NONE', 'N/A') THEN NULL
					WHEN UPPER(TRIM(order_item_id)) LIKE 'ITEM[0-9]%' THEN 'ITEM-' + SUBSTRING(UPPER(TRIM(order_item_id)), 5, LEN(UPPER(TRIM(order_item_id))))
					ELSE UPPER(TRIM(order_item_id))
				END AS order_item_id,
				CASE
					WHEN UPPER(TRIM(order_id)) IN ('', '-', 'NA', 'NULL', 'NONE', 'N/A') THEN NULL
					WHEN UPPER(TRIM(order_id)) LIKE 'ORD[0-9]%' THEN 'ORD-' + SUBSTRING(UPPER(TRIM(order_id)), 4, LEN(UPPER(TRIM(order_id))))
					ELSE UPPER(TRIM(order_id))
				END AS order_id,
				CASE
					WHEN UPPER(TRIM(product_id)) IN ('', '-', 'NA', 'NULL', 'NONE', 'N/A') THEN NULL
					WHEN UPPER(TRIM(product_id)) LIKE 'PROD[0-9]%' THEN 'PROD-' + SUBSTRING(UPPER(TRIM(product_id)), 5, LEN(UPPER(TRIM(product_id))))
					ELSE UPPER(TRIM(product_id))
				END AS product_id,
				CASE
					WHEN TRY_CAST(TRY_CAST(TRIM(quantity) AS FLOAT) AS INT) <= 0 THEN NULL
					WHEN TRY_CAST(TRY_CAST(TRIM(quantity) AS FLOAT) AS INT) >= 1 THEN TRY_CAST(TRY_CAST(TRIM(quantity) AS FLOAT) AS INT)
					WHEN TRIM(quantity) LIKE '[0-9]%' THEN TRY_CAST(LEFT(TRIM(quantity), 1) AS INT)
					WHEN UPPER(TRIM(quantity)) = 'ONE' THEN 1
					WHEN UPPER(TRIM(quantity)) = 'TWO' THEN 2
					WHEN UPPER(TRIM(quantity)) = 'THREE' THEN 3
					WHEN UPPER(TRIM(quantity)) = 'FOUR' THEN 4

					WHEN UPPER(TRIM(quantity)) = 'FIVE' THEN 5
					ELSE NULL
				END AS quantity,
				TRY_CAST(REPLACE(REPLACE(REPLACE(UPPER(unit_price), 'NGN', ''), 'N', ''), ',', '') AS DECIMAL(10, 2)) AS unit_price,
				CASE
					WHEN TRY_CAST(REPLACE(TRIM(discount_pct), '%', '') AS DECIMAL(5,2)) IS NULL THEN 0
					WHEN discount_pct LIKE '%.%' AND TRY_CAST(REPLACE(TRIM(discount_pct), '%', '') AS DECIMAL(5,2)) <= 1 
					THEN TRY_CAST(REPLACE(TRIM(discount_pct), '%', '') AS DECIMAL(5,2)) * 100
					ELSE TRY_CAST(REPLACE(TRIM(discount_pct), '%', '') AS DECIMAL(5,2))
				END AS discount_pct,
				TRY_CAST(REPLACE(REPLACE(REPLACE(UPPER(line_total), 'NGN', ''), 'N', ''), ',', '') AS DECIMAL(18, 2)) AS line_total,
				load_id,
				source_row_number,
				ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(order_item_id)) ORDER BY source_row_number) AS rn
			INTO #order_items_cleaned
			FROM stg.order_items;

			ALTER TABLE #order_items_cleaned 
			ADD reject_rule NVARCHAR(20) NULL, 
				reject_reason NVARCHAR(200) NULL, 
				dq_price_fallback BIT NOT NULL DEFAULT 0;

			CREATE INDEX ix_order_items_order ON #order_items_cleaned (order_id);
			CREATE INDEX ix_order_items_product ON #order_items_cleaned (product_id);

			-- label duplicate order_item_id
			UPDATE #order_items_cleaned
			SET reject_rule = 'BR-I06',
				reject_reason = 'Duplicate order_item_id; first row in file was kept'
			WHERE rn > 1;

			-- label invalid or missing quantity
			UPDATE #order_items_cleaned
			SET reject_rule = 'BR-I02',
				reject_reason = 'Quantity missing, invalid  or below 1'
			WHERE reject_rule IS NULL AND (quantity IS NULL OR quantity < 1);

			-- label orders not found in cln.orders
			UPDATE i
			SET reject_rule = 'BR-I01',
				reject_reason = 'order_id not found in cln.orders'
			FROM #order_items_cleaned AS i
			WHERE i.reject_rule IS NULL AND NOT EXISTS 
			(
				SELECT 1
				FROM cln.orders AS o
				WHERE i.order_id = o.order_id
			);

			-- label products not found in cln.product 
			UPDATE i
			SET reject_rule = 'BR-I01',
				reject_reason = 'product_id not found in cln.products'
			FROM #order_items_cleaned AS i
			WHERE i.reject_rule IS NULL AND NOT EXISTS 
			(
				SELECT 1
				FROM cln.products AS p
				WHERE i.product_id = p.product_id
			);

			-- Fix missing price from the product price (BR-I05)
			UPDATE i
			SET i.unit_price = p.unit_price,
				i.dq_price_fallback =  1
			FROM #order_items_cleaned AS i
			JOIN cln.products AS p
			ON i.product_id = p.product_id
			WHERE i.reject_rule IS NULL AND (i.unit_price IS NULL OR i.unit_price <= 0);

			-- recalculate the line total (BR-I04)
			UPDATE #order_items_cleaned
			SET line_total = ROUND(quantity * unit_price * (1 - discount_pct / 100.0), 2)
			WHERE reject_rule IS NULL;

			PRINT '========================================================';
			PRINT 'LOADING err.rejected_rows TABLE';
			PRINT '========================================================';
			DELETE FROM err.rejected_rows  WHERE table_name = 'order_items';
			INSERT INTO err.rejected_rows (load_id, table_name, source_row_number, record_key, rule_id, reason)
			SELECT 
				load_id, 'order_items', source_row_number, order_item_id, reject_rule, reject_reason
			FROM #order_items_cleaned
			WHERE reject_rule IS NOT NULL;
			PRINT '========================================================';
			PRINT 'LOADING err.rejected_rows TABLE COMPLETED';
			PRINT '========================================================';

			PRINT '========================================================';
			PRINT 'LOADING INTO cln.order_items TABLE';
			PRINT '========================================================';
			DELETE FROM cln.order_items;
			INSERT INTO cln.order_items (order_item_id, order_id, product_id, quantity, unit_price,
				discount_pct, line_total, dq_price_fallback, load_id, source_row_number
			)
			SELECT 
				order_item_id, order_id, product_id, quantity, unit_price,
				discount_pct, line_total, dq_price_fallback, load_id, source_row_number
			FROM #order_items_cleaned
			WHERE reject_rule IS NULL;
			PRINT '========================================================';
			PRINT 'LOADING cln.order_items TABLE COMPLETED';
			PRINT '========================================================';
		COMMIT;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK;
		THROW;
	END CATCH
END;
GO
