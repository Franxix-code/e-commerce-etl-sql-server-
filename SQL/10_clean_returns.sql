/* =====================================================================
   File     : 10_clean_returns.sql
   Purpose  : Cleans stg.returns and loads cln.returns (rules BR-T01 to BR-T05).
   Needs    : cln.order_items and cln.orders loaded (foreign keys)
   ===================================================================== */

CREATE OR ALTER PROCEDURE etl.usp_load_cln_returns
AS
BEGIN 
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	BEGIN TRY
		BEGIN TRAN;
			DROP TABLE IF EXISTS #returns_cleaned;
			SELECT 
				CASE
					WHEN UPPER(TRIM(return_id)) IN ('', '-', 'NA', 'NULL', 'NONE', 'N/A') THEN NULL
					WHEN UPPER(TRIM(return_id)) LIKE 'RET[0-9]%' THEN 'RET-' + SUBSTRING(UPPER(TRIM(return_id)), 4, LEN(UPPER(TRIM(return_id))))
					ELSE UPPER(TRIM(return_id))
				END AS return_id,
				CASE
					WHEN UPPER(TRIM(order_item_id)) IN ('', '-', 'NA', 'NULL', 'NONE', 'N/A') THEN NULL
					WHEN UPPER(TRIM(order_item_id)) LIKE 'ITEM[0-9]%' THEN 'ITEM-' + SUBSTRING(UPPER(TRIM(order_item_id)), 5, LEN(UPPER(TRIM(order_item_id))))
					ELSE UPPER(TRIM(order_item_id))
				END AS order_item_id,
				CASE
					WHEN TRIM(return_date) LIKE '[0-9][0-9][0-9][0-9]/[0-9][0-9]/[0-9][0-9]' 
					THEN TRY_CONVERT(DATE, REPLACE(TRIM(return_date), '/', '-'), 23)  -- 2024/03/05
					WHEN TRIM(return_date) LIKE '[0-9][0-9]/[0-9][0-9]/[0-9][0-9][0-9][0-9]' 
					THEN TRY_CONVERT(DATE, TRIM(return_date), 103)  -- 05/03/2023 (day first)
					WHEN TRIM(return_date) LIKE '[0-9][0-9].[0-9][0-9].[0-9][0-9][0-9][0-9]' 
					THEN TRY_CONVERT(DATE, REPLACE(TRIM(return_date), '.', '-'), 104)  -- 05.03.2023 (day first)
					WHEN TRIM(return_date) LIKE '[0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9]' 
					THEN TRY_CONVERT(DATE, TRIM(return_date), 110)  -- 03-05-2023 (month first)
					WHEN TRIM(return_date) LIKE '[0-9][0-9]-[0-9][0-9]-[0-9][0-9]' 
					THEN TRY_CONVERT(DATE, TRIM(return_date), 5)  -- 03-05-2023 (day first)
					WHEN TRIM(return_date) LIKE '[0-9][0-9] [A-Za-z][A-Za-z][A-Za-z] [0-9][0-9][0-9][0-9]' 
					THEN TRY_CONVERT(DATE, TRIM(return_date), 106)  -- 05 Mar 2023 
					WHEN TRIM(return_date) LIKE '[A-Za-z]%[0-9][0-9], [0-9][0-9][0-9][0-9]' 
					THEN TRY_CONVERT(DATE, TRIM(return_date), 107)  -- March 05, 2023 
					WHEN TRIM(return_date) LIKE '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]%'
					THEN TRY_CONVERT(DATE, LEFT(TRIM(return_date), 10), 23) -- 2023-03-05 00:00:00
				END AS return_date,
				CASE
					WHEN UPPER(TRIM(reason)) IN ('DAMAGED', 'ITEM DAMAGED') THEN 'Damaged'
					WHEN UPPER(TRIM(reason)) IN ('WRONG ITEM', 'WRONG PRODUCT', 'INCORRECT ITEM') THEN 'Wrong item'
					WHEN UPPER(TRIM(reason)) IN ('NAD', 'NOT AS DESCRIBED') THEN 'Not as described'
					WHEN UPPER(TRIM(reason)) IN ('CUSTOMER CHANGED MIND', 'CHANGED MIND') THEN 'Changed mind'
					WHEN UPPER(TRIM(reason)) IN ('DEFECTIVE', 'FAULTY') THEN 'Defective'
					WHEN UPPER(TRIM(reason)) = 'LATE DELIVERY' THEN 'Late delivery'
					WHEN UPPER(TRIM(reason)) = 'TOO SMALL' THEN 'Too small'
					WHEN UPPER(TRIM(reason)) = 'TOO LARGE' THEN 'Too large'
					ELSE NULL
				END AS reason,
				TRY_CAST(NULLIF(TRIM(REPLACE(REPLACE(REPLACE(UPPER(refund_amount), 'NGN', ''), 'N', ''), ',', '')), '') AS DECIMAL(10, 2)) AS refund_amount,
				CASE	
					WHEN UPPER(TRIM(return_status)) IN ('REFUNDED', 'COMPLETED') THEN 'Refunded'
					WHEN UPPER(TRIM(return_status)) IN ('REJECTED', 'DECLINED') THEN 'Rejected'
					WHEN UPPER(TRIM(return_status)) IN ('OPEN', 'PENDING') THEN 'Pending'
					WHEN UPPER(TRIM(return_status)) = 'APPROVED' THEN 'Approved'
					ELSE NULL
				END AS return_status,
				CASE
					WHEN UPPER(TRIM(item_condition)) IN ('NEW', 'BRAND NEW') THEN 'New'
					WHEN UPPER(TRIM(item_condition)) IN ('OPENED', 'OPEN') THEN 'Opened'
					WHEN UPPER(TRIM(item_condition)) IN ('DAMAGED', 'BROKEN') THEN 'Damaged'
					WHEN UPPER(TRIM(item_condition)) = 'USED' THEN 'Used'
					ELSE NULL
				END AS item_condition,
				load_id,
				source_row_number,
				ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(return_id)) ORDER BY source_row_number) AS rn
			INTO #returns_cleaned
			FROM stg.returns;

			ALTER TABLE #returns_cleaned 
			ADD reject_rule NVARCHAR(20) NULL, 
				reject_reason NVARCHAR(200) NULL,
				dq_return_window BIT NOT NULL DEFAULT 0,
				dq_refund_capped BIT NOT NULL DEFAULT 0;

			CREATE INDEX ix_ret_item ON #returns_cleaned (order_item_id);

			-- BR-T05: duplicate return_id
			UPDATE #returns_cleaned
			SET reject_rule = 'BR-T05',
				reject_reason = 'Duplicate return_id, first row in file was kept'
			WHERE rn > 1;

			-- BR-T01: order_item_id not exists in cln.order_items
			UPDATE r
			SET reject_rule = 'BR-T01',
				reject_reason = 'order_item_id not found in cln.order_items'
			FROM #returns_cleaned AS r
			WHERE r.reject_rule IS NULL AND NOT EXISTS 
			(
				SELECT 1
				FROM cln.order_items AS o
				WHERE o.order_item_id = r.order_item_id
			);
	
			--BR-T03: a rejected return has a refund of 0
			UPDATE #returns_cleaned
			SET refund_amount = 0
			WHERE reject_rule IS NULL AND return_status = 'Rejected' AND refund_amount <> 0;

			-- BR-T03: the refund cannot exceed the item's line total 
			UPDATE r
			SET r.refund_amount = o.line_total,
				r.dq_refund_capped = 1
			FROM #returns_cleaned AS r
			JOIN cln.order_items AS o
			ON o.order_item_id = r.order_item_id
			WHERE r.reject_rule IS NULL AND r.refund_amount > o.line_total + 0.01; -- +0.01 ALLOWS FOR A CENT OF ROUNDING

			-- BR-T02: return more than 45 days after order date or before it
			UPDATE r
			SET r.dq_return_window = 1
			FROM #returns_cleaned AS r
			JOIN cln.order_items AS oi
			ON oi.order_item_id = r.order_item_id
			JOIN cln.orders AS o
			ON o.order_id = oi.order_id
			WHERE r.reject_rule IS NULL AND (r.return_date < o.order_date OR DATEDIFF(DAY, o.order_date, r.return_date) > 45); 

			PRINT '========================================================';
			PRINT 'LOADING INTO err.rejected_rows TABLE';
			PRINT '========================================================';
			DELETE FROM err.rejected_rows WHERE table_name = 'returns';
			INSERT INTO err.rejected_rows (load_id, table_name, source_row_number, record_key, rule_id, reason)
			SELECT
				load_id, 'returns', source_row_number, return_id, reject_rule, reject_reason
			FROM #returns_cleaned
			WHERE reject_rule IS NOT NULL;
			PRINT '========================================================';
			PRINT 'LOADING err.rejected_rows TABLE COMPLETED';
			PRINT '========================================================';

			PRINT '========================================================';
			PRINT 'LOADING INTO cln.returns TABLE';
			PRINT '========================================================';
			DELETE FROM cln.returns;
			INSERT INTO cln.returns (return_id, order_item_id, return_date, reason, refund_amount,
				return_status, item_condition, dq_return_window, dq_refund_capped, load_id,source_row_number
			)	
			SELECT 
				return_id, order_item_id, return_date, reason, refund_amount,
				return_status, item_condition, dq_return_window, dq_refund_capped, load_id,source_row_number
			FROM #returns_cleaned
			WHERE reject_rule IS NULL;
			PRINT '========================================================';
			PRINT 'LOADING cln.returns TABLE COMPLETED';
			PRINT '========================================================';
		COMMIT;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK;
		THROW;
	END CATCH
END;
GO
