/* =====================================================================
   File     : 09_clean_reviews.sql
   Purpose  : Cleans stg.reviews and loads cln.reviews (rules BR-R01 to BR-R06).
   Needs    : cln.customers, cln.products and cln.orders loaded (foreign keys)
   ===================================================================== */

CREATE OR ALTER PROCEDURE etl.usp_load_cln_reviews
AS
BEGIN 
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	BEGIN TRY
		BEGIN TRAN;
			DROP TABLE IF EXISTS #reviews_cleaned;
			SELECT 
				CASE
					WHEN UPPER(TRIM(review_id)) IN ('', '-', 'NA', 'NULL', 'NONE', 'N/A') THEN NULL
					WHEN UPPER(TRIM(review_id)) LIKE 'REV[0-9]%' THEN 'REV-' + SUBSTRING(UPPER(TRIM(review_id)), 4, LEN(UPPER(TRIM(review_id))))
					ELSE UPPER(TRIM(review_id))
				END AS review_id,
				CASE
					WHEN UPPER(TRIM(customer_id)) IN ('', '-', 'NA', 'NULL', 'NONE', 'N/A') THEN NULL
					WHEN UPPER(TRIM(customer_id)) LIKE 'CUST[0-9]%' THEN 'CUST-' + SUBSTRING(UPPER(TRIM(customer_id)), 5, LEN(UPPER(TRIM(customer_id))))
					ELSE UPPER(TRIM(customer_id))
				END AS customer_id,
				CASE
					WHEN UPPER(TRIM(product_id)) IN ('', '-', 'NA', 'NULL', 'NONE', 'N/A') THEN NULL
					WHEN UPPER(TRIM(product_id)) LIKE 'PROD[0-9]%' THEN 'PROD-' + SUBSTRING(UPPER(TRIM(product_id)), 5, LEN(UPPER(TRIM(product_id))))
					ELSE UPPER(TRIM(product_id))
				END AS product_id,
				CASE
					WHEN UPPER(TRIM(order_id)) IN ('', '-', 'NA', 'NULL', 'NONE', 'N/A') THEN NULL
					WHEN UPPER(TRIM(order_id)) LIKE 'ORD[0-9]%' THEN 'ORD-' + SUBSTRING(UPPER(TRIM(order_id)), 4, LEN(UPPER(TRIM(order_id))))
					ELSE UPPER(TRIM(order_id))
				END AS order_id,
				CASE
					WHEN TRY_CAST(TRY_CAST(TRIM(rating) AS FLOAT) AS INT) > 5 OR TRY_CAST(TRY_CAST(TRIM(rating) AS FLOAT) AS INT) <= 0 THEN NULL
					WHEN TRY_CAST(TRY_CAST(TRIM(rating) AS FLOAT) AS INT) IN (1, 2, 3, 4, 5) THEN TRY_CAST(TRY_CAST(TRIM(rating) AS FLOAT) AS INT)
					WHEN TRIM(rating) LIKE '[0-9]%' THEN TRY_CAST(LEFT(TRIM(rating), 1) AS INT)
					WHEN UPPER(TRIM(rating)) = 'ONE' THEN 1
					WHEN UPPER(TRIM(rating)) = 'TWO' THEN 2
					WHEN UPPER(TRIM(rating)) = 'THREE' THEN 3
					WHEN UPPER(TRIM(rating)) = 'FOUR' THEN 4
					WHEN UPPER(TRIM(rating)) = 'FIVE' THEN 5
					ELSE NULL
				END AS rating,
				CASE
					WHEN TRIM(review_text) IN ('', '-', 'NULL', 'NONE', 'NA', 'N/A') THEN NULL
					ELSE TRIM(review_text)
				END AS review_text,
				CASE
					WHEN TRIM(review_date) LIKE '[0-9][0-9][0-9][0-9]/[0-9][0-9]/[0-9][0-9]' 
					THEN TRY_CONVERT(DATE, REPLACE(TRIM(review_date), '/', '-'), 23)  -- 2024/03/05
					WHEN TRIM(review_date) LIKE '[0-9][0-9]/[0-9][0-9]/[0-9][0-9][0-9][0-9]' 
					THEN TRY_CONVERT(DATE, TRIM(review_date), 103)  -- 05/03/2023 (day first)
					WHEN TRIM(review_date) LIKE '[0-9][0-9].[0-9][0-9].[0-9][0-9][0-9][0-9]' 
					THEN TRY_CONVERT(DATE, REPLACE(TRIM(review_date), '.', '-'), 104)  -- 05.03.2023 (day first)
					WHEN TRIM(review_date) LIKE '[0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9]' 
					THEN TRY_CONVERT(DATE, TRIM(review_date), 110)  -- 03-05-2023 (month first)
					WHEN TRIM(review_date) LIKE '[0-9][0-9]-[0-9][0-9]-[0-9][0-9]' 
					THEN TRY_CONVERT(DATE, TRIM(review_date), 5)  -- 03-05-2023 (day first)
					WHEN TRIM(review_date) LIKE '[0-9][0-9] [A-Za-z][A-Za-z][A-Za-z] [0-9][0-9][0-9][0-9]' 
					THEN TRY_CONVERT(DATE, TRIM(review_date), 106)  -- 05 Mar 2023 
					WHEN TRIM(review_date) LIKE '[A-Za-z]%[0-9][0-9], [0-9][0-9][0-9][0-9]' 
					THEN TRY_CONVERT(DATE, TRIM(review_date), 107)  -- March 05, 2023 
					WHEN TRIM(review_date) LIKE '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]%'
					THEN TRY_CONVERT(DATE, LEFT(TRIM(review_date), 10), 23) -- 2023-03-05 00:00:00
				END AS review_date,
				CASE 
					WHEN TRIM(helpful_votes) IN ('', '-', 'NULL', 'NONE', 'NA', 'N/A') THEN NULL
					ELSE TRY_CAST(TRIM(helpful_votes) AS INT)
				END AS helpful_votes,
				CASE
					WHEN UPPER(TRIM(verified_purchase)) IN ('N', 'FALSE', 'NO', '0') THEN 0
					WHEN UPPER(TRIM(verified_purchase)) IN ('Y', 'TRUE', 'YES', '1')  THEN 1
					ELSE NULL
				END AS verified_purchase,
				load_id,
				source_row_number,
				ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(review_id)) ORDER BY source_row_number) AS rn
			INTO #reviews_cleaned
			FROM stg.reviews;

			ALTER TABLE #reviews_cleaned 
			ADD reject_rule NVARCHAR(50) NULL, 
				reject_reason NVARCHAR(200) NULL,
				dq_invalid_rating BIT NOT NULL DEFAULT 0,
				dq_date_before_order BIT NOT NULL DEFAULT 0;

			CREATE INDEX ix_rev_customers ON #reviews_cleaned (customer_id);
			CREATE INDEX ix_rev_products ON #reviews_cleaned (product_id);
			CREATE INDEX ix_rev_orders ON #reviews_cleaned (order_id);

			-- BR-R06: Duplicate review_id
			UPDATE #reviews_cleaned
			SET reject_rule = 'BR-R06',
				reject_reason = 'Duplicate review_id, first row in file was kept'
			WHERE rn > 1;

			-- BR-R01: customers, products and orders must all exists
			UPDATE r
			SET reject_rule = 'BR-R01',
				reject_reason = 'customer_id not found in cln.customers'
			FROM #reviews_cleaned AS r
			WHERE reject_rule IS NULL AND NOT EXISTS 
			(
				SELECT 1
				FROM cln.customers AS c
				WHERE c.customer_id = r.customer_id
			);

			UPDATE r
			SET reject_rule = 'BR-R01',
				reject_reason = 'product_id not found in cln.products'
			FROM #reviews_cleaned AS r
			WHERE reject_rule IS NULL AND NOT EXISTS 
			(
				SELECT 1
				FROM cln.products AS p
				WHERE p.product_id = r.product_id
			);

			UPDATE r
			SET reject_rule = 'BR-R01',
				reject_reason = 'order_id not found in cln.orders'
			FROM #reviews_cleaned AS r
			WHERE reject_rule IS NULL AND NOT EXISTS 
			(
				SELECT 1
				FROM cln.orders AS o
				WHERE o.order_id = r.order_id
			);

			-- BR-R03: one review per customer + product + order; keep the latest
			WITH ranked AS (
				SELECT 
					reject_rule,
					reject_reason,
					ROW_NUMBER() OVER (PARTITION BY customer_id, product_id, order_id ORDER BY review_date DESC, source_row_number) AS combo_rn
				FROM #reviews_cleaned
				WHERE reject_rule IS NULL
			)
			UPDATE ranked
			SET reject_rule = 'BR-R03',
				reject_reason = 'Older review from the same customer, product and order'
			WHERE combo_rn > 1;

			-- BR-R02: the rating CASE above already sets values outside 1 to 5 to NULL, so flag every rating
			-- that was present in the source but is NULL after cleaning (disguised nulls do not count)
			UPDATE r
			SET dq_invalid_rating = 1
			FROM #reviews_cleaned AS r
			JOIN stg.reviews AS s ON s.source_row_number = r.source_row_number
			WHERE r.reject_rule IS NULL AND r.rating IS NULL
			AND ISNULL(UPPER(TRIM(s.rating)), '') NOT IN ('', '-', 'NA', 'NULL', 'NONE', 'N/A');

			-- BR-R04: reviews written before order date 
			UPDATE r
			SET dq_date_before_order = 1
			FROM #reviews_cleaned AS r
			JOIN cln.orders AS o
			ON o.order_id = r.order_id
			WHERE r.reject_rule IS NULL AND r.review_date < o.order_date;

			PRINT '========================================================';
			PRINT 'LOADING err.rejected_rows TABLE';
			PRINT '========================================================';
			DELETE FROM err.rejected_rows WHERE table_name = 'reviews';
			INSERT INTO err.rejected_rows (load_id, table_name, source_row_number, record_key, rule_id, reason)
			SELECT
				load_id, 'reviews', source_row_number, review_id, reject_rule, reject_reason
			FROM #reviews_cleaned
			WHERE reject_rule IS NOT NULL;
			PRINT '========================================================';
			PRINT 'LOADING err.rejected_rows TABLE';
			PRINT '========================================================';

			PRINT '========================================================';
			PRINT 'LOADING INTO cln.reviews TABLE';
			PRINT '========================================================';
			DELETE FROM cln.reviews;
			INSERT INTO cln.reviews (review_id, customer_id, product_id, order_id, rating, review_text, review_date,
				helpful_votes, verified_purchase, dq_invalid_rating, dq_date_before_order, load_id,source_row_number)
			SELECT
				review_id, customer_id, product_id, order_id, rating, review_text, review_date,
				helpful_votes, verified_purchase, dq_invalid_rating, dq_date_before_order, load_id,source_row_number
			FROM #reviews_cleaned
			WHERE reject_rule IS NULL;
			PRINT '========================================================';
			PRINT 'LOADING cln.reviews TABLE COMPLETED';
			PRINT '========================================================';
		COMMIT;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK;
		THROW;
	END CATCH
END;
GO
