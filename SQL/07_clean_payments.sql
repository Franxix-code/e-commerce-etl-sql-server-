/* =====================================================================
   File     : 07_clean_payments.sql
   Purpose  : Cleans stg.payments and loads cln.payments (rules BR-Y01 to BR-Y08).
   Needs    : cln.orders loaded and 05_update_order_totals run (BR-Y06 compares with the order total)
   ===================================================================== */

CREATE OR ALTER PROCEDURE etl.usp_load_cln_payments
AS
BEGIN 
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	BEGIN TRY
		BEGIN TRAN;
			DROP TABLE IF EXISTS #payments_cleaned;
			SELECT 
				CASE	
					WHEN UPPER(TRIM(payment_id)) IN ('', '-', 'NA', 'N/A', 'NULL', 'NONE') THEN NULL
					WHEN UPPER(TRIM(payment_id)) LIKE 'PAY[0-9]%' THEN 'PAY-' + SUBSTRING(UPPER(TRIM(payment_id)), 4, LEN(UPPER(TRIM(payment_id))))
					ELSE UPPER(TRIM(payment_id))
				END AS payment_id,
				CASE	
					WHEN UPPER(TRIM(order_id)) IN ('', '-', 'NA', 'N/A', 'NULL', 'NONE') THEN NULL
					WHEN UPPER(TRIM(order_id)) LIKE 'ORD[0-9]%' THEN 'ORD-' + SUBSTRING(UPPER(TRIM(order_id)), 4, LEN(UPPER(TRIM(order_id))))
					ELSE UPPER(TRIM(order_id))
				END AS order_id,
				CASE
					WHEN TRIM(payment_date) LIKE '[0-9][0-9][0-9][0-9]/[0-9][0-9]/[0-9][0-9]' 
					THEN TRY_CONVERT(DATE, REPLACE(TRIM(payment_date), '/', '-'), 23)						-- 2024/03/05
					WHEN TRIM(payment_date) LIKE '[0-9][0-9]/[0-9][0-9]/[0-9][0-9][0-9][0-9]' 
					THEN TRY_CONVERT(DATE, TRIM(payment_date), 103)											-- 05/03/2023 (day first)
					WHEN TRIM(payment_date) LIKE '[0-9][0-9].[0-9][0-9].[0-9][0-9][0-9][0-9]' 
					THEN TRY_CONVERT(DATE, REPLACE(TRIM(payment_date), '.', '-'), 104)						-- 05.03.2023 (day first)
					WHEN TRIM(payment_date) LIKE '[0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9]' 
					THEN TRY_CONVERT(DATE, TRIM(payment_date), 110)											-- 03-05-2023 (month first)
					WHEN TRIM(payment_date) LIKE '[0-9][0-9]-[0-9][0-9]-[0-9][0-9]' 
					THEN TRY_CONVERT(DATE, TRIM(payment_date), 5)											-- 03-05-2023 (day first)
					WHEN TRIM(payment_date) LIKE '[0-9][0-9] [A-Za-z][A-Za-z][A-Za-z] [0-9][0-9][0-9][0-9]' 
					THEN TRY_CONVERT(DATE, TRIM(payment_date), 106)											-- 05 Mar 2023 
					WHEN TRIM(payment_date) LIKE '[A-Za-z]%[0-9][0-9], [0-9][0-9][0-9][0-9]' 
					THEN TRY_CONVERT(DATE, TRIM(payment_date), 107)											-- March 05, 2023 
					WHEN TRIM(payment_date) LIKE '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]%'
					THEN TRY_CONVERT(DATE, LEFT(TRIM(payment_date), 10), 23)								-- 2023-03-05 00:00:00
				END AS payment_date,
				CASE
					WHEN UPPER(TRIM(payment_method)) LIKE '%TRANSFER%' THEN 'Bank Transfer'
					WHEN UPPER(TRIM(payment_method)) LIKE '%DELIVERY%' OR UPPER(TRIM(payment_method)) = 'POD' THEN 'Pay on Delivery'
					WHEN UPPER(TRIM(payment_method)) LIKE '%WALLET%' THEN 'Wallet'
					WHEN UPPER(TRIM(payment_method)) LIKE '%USSD%' THEN 'USSD'
					WHEN UPPER(TRIM(payment_method)) LIKE '%CARD%' THEN 'Card'
					WHEN UPPER(TRIM(payment_method)) LIKE '%POS%' THEN 'POS'
					ELSE NULL
				END AS payment_method,
				TRY_CAST(NULLIF(TRIM(REPLACE(REPLACE(REPLACE(UPPER(amount), 'NGN', ''), 'N', ''), ',', '')), '') AS DECIMAL(10, 2)) AS amount,
				CASE 
					WHEN UPPER(TRIM(currency)) IN ('N', 'NAIRA', 'NGN') THEN 'NGN'
					ELSE NULL
				END AS currency,
				CASE
					WHEN UPPER(TRIM(payment_status)) IN ('PAID', 'SUCCESS', 'SUCCESSFUL', 'COMPLETED') THEN 'Success'
					WHEN UPPER(TRIM(payment_status)) = 'PENDING' THEN 'Pending'
					WHEN UPPER(TRIM(payment_status)) IN ('DECLINED', 'FAILED') THEN 'Failed'
					WHEN UPPER(TRIM(payment_status)) = 'REFUNDED' THEN 'Refunded'
				END AS payment_status,
				CASE
					WHEN UPPER(TRIM(transaction_ref)) IN ('', '-', 'NA', 'N/A', 'NONE', 'NULL') THEN NULL
					ELSE UPPER(TRIM(transaction_ref))
				END AS transaction_ref,
				load_id,
				source_row_number,
				ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(payment_id)) ORDER BY source_row_number) rn
			INTO #payments_cleaned
			FROM stg.payments;

			ALTER TABLE #payments_cleaned ADD reject_rule NVARCHAR(20) NULL, reject_reason NVARCHAR(200) NULL;
			CREATE INDEX ix_pay_order ON #payments_cleaned (order_id);

			-- reject duplicate paymentid
			UPDATE p
			SET reject_rule = 'BR-Y08',
				reject_reason = 'Duplicate payment_id, first row in file was kept'
			FROM #payments_cleaned AS p
			WHERE rn > 1;

			-- order_id not found in cln.orders table
			UPDATE p
			SET reject_rule = 'BR-Y01',
				reject_reason = 'order_id not found in cln.orders'
			FROM #payments_cleaned AS p
			WHERE p.reject_rule IS NULL AND NOT EXISTS 
			(
				SELECT 1
				FROM cln.orders AS o
				WHERE o.order_id = p.order_id
			);


			ALTER TABLE #payments_cleaned
			ADD	dq_ref_issue NVARCHAR(20),
				dq_multiple_success BIT NOT NULL DEFAULT 0,
				dq_partial_payment BIT NOT NULL DEFAULT 0,
				dq_date_before_order BIT NOT NULL DEFAULT 0;

			-- BR-Y05: missing transaction ref (pay on delivery may be empty) or duplicate ref
			UPDATE #payments_cleaned
			SET dq_ref_issue =  'Missing'
			WHERE reject_rule IS NULL AND transaction_ref IS NULL AND payment_method <> 'Pay on Delivery';

			UPDATE #payments_cleaned
			SET dq_ref_issue = 'Duplicate'
			WHERE reject_rule IS NULL AND transaction_ref IN 
			(
				SELECT transaction_ref
				FROM #payments_cleaned
				WHERE reject_rule IS NULL AND transaction_ref IS NOT NULL
				GROUP BY transaction_ref
				HAVING COUNT(*) > 1
			);

			-- BR-Y04: more than one succes for same order
			UPDATE #payments_cleaned
			SET dq_multiple_success = 1
			WHERE reject_rule IS NULL AND payment_status = 'Success'
			AND order_id IN 
			(
				SELECT order_id
				FROM #payments_cleaned
				WHERE reject_rule IS NULL AND payment_status = 'Success'
				GROUP BY order_id
				HAVING COUNT(*) > 1
			);

			-- BR-Y06: succesful payment differs from the order total
			UPDATE p
			SET dq_partial_payment = 1
			FROM #payments_cleaned AS p
			JOIN cln.orders AS o
			ON p.order_id = o.order_id
			WHERE p.reject_rule IS NULL AND p.payment_status = 'Success' AND p.amount IS NOT NULL
			AND ABS(p.amount - COALESCE(o.total_amount, o.total_amount_calc)) > 1.00;

			-- BR-Y07: payment before order date
			UPDATE p
			SET dq_date_before_order = 1
			FROM #payments_cleaned AS p
			JOIN cln.orders AS o
			ON o.order_id = p.order_id
			WHERE p.reject_rule IS NULL AND p.payment_date < o.order_date;

			PRINT '========================================================';
			PRINT 'LOADING INTO err.rejected_rows TABLE';
			PRINT '========================================================';
			DELETE FROM err.rejected_rows
			WHERE table_name = 'payments';
			INSERT INTO err.rejected_rows (load_id, table_name, source_row_number, record_key, rule_id, reason)	
			SELECT
				load_id, 'payments', source_row_number, payment_id, reject_rule, reject_reason
			FROM #payments_cleaned
			WHERE reject_rule IS NOT NULL;
			PRINT '========================================================';
			PRINT 'LOADING err.rejected_rows TABLE COMPLETED';
			PRINT '========================================================';

			PRINT '========================================================';
			PRINT 'LOADING INTO cln.payments TABLE ';
			PRINT '========================================================';
			DELETE FROM cln.payments;
			INSERT INTO cln.payments (payment_id, order_id, payment_date, payment_method, amount, currency,
				payment_status, transaction_ref, dq_ref_issue, dq_multiple_success, dq_partial_payment,
				dq_date_before_order, load_id, source_row_number
			)
			SELECT 
				payment_id, order_id, payment_date, payment_method, amount, currency,
				payment_status, transaction_ref, dq_ref_issue, dq_multiple_success, dq_partial_payment,
				dq_date_before_order, load_id, source_row_number
			FROM #payments_cleaned
			WHERE reject_rule IS NULL;
			PRINT '========================================================';
			PRINT 'LOADING cln.payments TABLE COMPLETED';
			PRINT '========================================================';
		COMMIT;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK;
		THROW;
	END CATCH
END;
GO
