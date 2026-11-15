/* =====================================================================
   File     : 11_clean_support_tickets.sql
   Purpose  : Cleans stg.support_tickets and loads cln.support_tickets (rules BR-K01 to BR-K05).
   Needs    : cln.customers and cln.orders loaded (foreign keys)
   ===================================================================== */

CREATE OR ALTER PROCEDURE etl.usp_load_cln_support_tickets
AS
BEGIN
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	BEGIN TRY
		BEGIN TRAN;
			DROP TABLE IF EXISTS #support_tickets_cleaned;
			SELECT 
				CASE
					WHEN UPPER(TRIM(ticket_id)) IN ('', '-', 'NA', 'NULL', 'NONE', 'N/A') THEN NULL
					WHEN UPPER(TRIM(ticket_id)) LIKE 'TKT[0-9]%' THEN 'TKT-' + SUBSTRING(UPPER(TRIM(ticket_id)), 4, LEN(UPPER(TRIM(ticket_id))))
					ELSE UPPER(TRIM(ticket_id))
				END AS ticket_id,
				CASE
					WHEN UPPER(TRIM(customer_id)) IN ('', '-', 'NA', 'NULL', 'NONE', 'N/A') THEN NULL
					WHEN UPPER(TRIM(customer_id)) LIKE 'CUST[0-9]%' THEN 'CUST-' + SUBSTRING(UPPER(TRIM(customer_id)), 5, LEN(UPPER(TRIM(customer_id))))
					ELSE UPPER(TRIM(customer_id))
				END AS customer_id,
				CASE
					WHEN UPPER(TRIM(order_id)) IN ('', '-', 'NA', 'NULL', 'NONE', 'N/A') THEN NULL
					WHEN UPPER(TRIM(order_id)) LIKE 'ORD[0-9]%' THEN 'ORD-' + SUBSTRING(UPPER(TRIM(order_id)), 4, LEN(UPPER(TRIM(order_id))))
					ELSE UPPER(TRIM(order_id))
				END AS order_id,
				CASE
					WHEN TRIM(created_at) LIKE '[0-9][0-9][0-9][0-9]/[0-9][0-9]/[0-9][0-9]' 
					THEN TRY_CONVERT(DATE, REPLACE(TRIM(created_at), '/', '-'), 23)  -- 2024/03/05
					WHEN TRIM(created_at) LIKE '[0-9][0-9]/[0-9][0-9]/[0-9][0-9][0-9][0-9]' 
					THEN TRY_CONVERT(DATE, TRIM(created_at), 103)  -- 05/03/2023 (day first)
					WHEN TRIM(created_at) LIKE '[0-9][0-9].[0-9][0-9].[0-9][0-9][0-9][0-9]' 
					THEN TRY_CONVERT(DATE, REPLACE(TRIM(created_at), '.', '-'), 104)  -- 05.03.2023 (day first)
					WHEN TRIM(created_at) LIKE '[0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9]' 
					THEN TRY_CONVERT(DATE, TRIM(created_at), 110)  -- 03-05-2023 (month first)
					WHEN TRIM(created_at) LIKE '[0-9][0-9]-[0-9][0-9]-[0-9][0-9]' 
					THEN TRY_CONVERT(DATE, TRIM(created_at), 5)  -- 03-05-2023 (day first)
					WHEN TRIM(created_at) LIKE '[0-9][0-9] [A-Za-z][A-Za-z][A-Za-z] [0-9][0-9][0-9][0-9]' 
					THEN TRY_CONVERT(DATE, TRIM(created_at), 106)  -- 05 Mar 2023 
					WHEN TRIM(created_at) LIKE '[A-Za-z]%[0-9][0-9], [0-9][0-9][0-9][0-9]' 
					THEN TRY_CONVERT(DATE, TRIM(created_at), 107)  -- March 05, 2023 
					WHEN TRIM(created_at) LIKE '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]%'
					THEN TRY_CONVERT(DATE, LEFT(TRIM(created_at), 10), 23) -- 2023-03-05 00:00:00
				END AS created_at,
				CASE
					WHEN TRIM(resolved_at) LIKE '[0-9][0-9][0-9][0-9]/[0-9][0-9]/[0-9][0-9]' 
					THEN TRY_CONVERT(DATE, REPLACE(TRIM(resolved_at), '/', '-'), 23)  -- 2024/03/05
					WHEN TRIM(resolved_at) LIKE '[0-9][0-9]/[0-9][0-9]/[0-9][0-9][0-9][0-9]' 
					THEN TRY_CONVERT(DATE, TRIM(resolved_at), 103)  -- 05/03/2023 (day first)
					WHEN TRIM(resolved_at) LIKE '[0-9][0-9].[0-9][0-9].[0-9][0-9][0-9][0-9]' 
					THEN TRY_CONVERT(DATE, REPLACE(TRIM(resolved_at), '.', '-'), 104)  -- 05.03.2023 (day first)
					WHEN TRIM(resolved_at) LIKE '[0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9]' 
					THEN TRY_CONVERT(DATE, TRIM(resolved_at), 110)  -- 03-05-2023 (month first)
					WHEN TRIM(resolved_at) LIKE '[0-9][0-9]-[0-9][0-9]-[0-9][0-9]' 
					THEN TRY_CONVERT(DATE, TRIM(resolved_at), 5)  -- 03-05-2023 (day first)
					WHEN TRIM(resolved_at) LIKE '[0-9][0-9] [A-Za-z][A-Za-z][A-Za-z] [0-9][0-9][0-9][0-9]' 
					THEN TRY_CONVERT(DATE, TRIM(resolved_at), 106)  -- 05 Mar 2023 
					WHEN TRIM(resolved_at) LIKE '[A-Za-z]%[0-9][0-9], [0-9][0-9][0-9][0-9]' 
					THEN TRY_CONVERT(DATE, TRIM(resolved_at), 107)  -- March 05, 2023 
					WHEN TRIM(resolved_at) LIKE '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]%'
					THEN TRY_CONVERT(DATE, LEFT(TRIM(resolved_at), 10), 23) -- 2023-03-05 00:00:00
				END AS resolved_at,
				CASE
					WHEN UPPER(TRIM(category)) IN ('DELIVERY DELAY', 'LATE DELIVERY') THEN 'Delivery delay'
					WHEN UPPER(TRIM(category)) IN ('PAYMENT PROBLEM', 'PAYMENT ISSUE') THEN 'Payment issue'
					WHEN UPPER(TRIM(category)) = 'REFUND' THEN 'Refund'
					WHEN UPPER(TRIM(category)) IN ('PRODUCT QUALITY', 'QUALITY') THEN 'Product quality'
					WHEN UPPER(TRIM(category)) = 'ACCOUNT' THEN 'Account'
					WHEN UPPER(TRIM(category)) = 'OTHER' THEN 'Other'
					ELSE NULL
				END AS category,
				CASE	
					WHEN UPPER(TRIM(priority)) IN ('P4', 'LOW', '1')  THEN 'Low'
					WHEN UPPER(TRIM(priority)) IN ('P3', 'MED', 'MEDIUM', 'NORMAL', '2') THEN 'Medium'
					WHEN UPPER(TRIM(priority)) IN ('P2', 'HIGH', '3') THEN 'High'
					WHEN UPPER(TRIM(priority)) IN ('P1', 'CRITICAL', 'URGENT', '4') THEN 'Urgent'
					ELSE NULL
				END AS priority,
				CASE
					WHEN UPPER(TRIM(status)) = 'OPEN' THEN 'Open'
					WHEN UPPER(TRIM(status)) = 'RESOLVED' THEN 'Resolved'
					WHEN UPPER(TRIM(status)) = 'CLOSED' THEN 'Closed'
					WHEN UPPER(TRIM(status)) = 'ESCALATED' THEN 'Escalated'
					ELSE NULL
				END AS status,
				CASE
					WHEN UPPER(TRIM(channel)) IN ('EMAIL', 'E-MAIL') THEN 'Email'
					WHEN UPPER(TRIM(channel)) IN ('PHONE', 'CALL') THEN 'Phone'
					WHEN UPPER(TRIM(channel)) IN ('CHAT', 'LIVE CHAT', 'WHATSAPP') THEN 'Chat'
					WHEN UPPER(TRIM(channel)) IN ('SOCIAL', 'INSTAGRAM DM', 'TWITTER', 'SOCIAL MEDIA') THEN 'Social Media'
					ELSE NULL
				END AS channel,
				-- BR-K04: 1 TO 5 ONLY
				CASE
					WHEN TRY_CAST(TRIM(satisfaction_score) AS INT) BETWEEN 1 AND 5  THEN TRY_CAST(TRIM(satisfaction_score) AS INT) 
				END AS satisfaction_score,
				load_id,
				source_row_number,
				ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(ticket_id)) ORDER BY source_row_number) AS rn
			INTO #support_tickets_cleaned
			FROM stg.support_tickets;


			ALTER TABLE #support_tickets_cleaned
			ADD reject_rule NVARCHAR(20) NULL,
				reject_reason NVARCHAR(200) NULL,
				dq_order_issue BIT NOT NULL DEFAULT 0,
				dq_resolution_issue BIT NOT NULL DEFAULT 0;

			CREATE INDEX ix_tkt_customer ON #support_tickets_cleaned (customer_id);

			-- BR-K05: duplicate ticket_id
			UPDATE #support_tickets_cleaned
			SET reject_rule = 'BR-K05',
				reject_reason = 'Duplicate ticket_id, first row in file was kept'
			WHERE rn > 1;

			-- BR-K01: customer not exists in cln.customers
			UPDATE t
			SET reject_rule = 'BR-K01',
				reject_reason = 'customer_id not found in cln.customers'
			FROM #support_tickets_cleaned AS t
			WHERE t.reject_rule IS NULL AND NOT EXISTS
			(
				SELECT 1
				FROM cln.customers AS c
				WHERE c.customer_id = t.customer_id
			);


			-- BR-K01: an order that does not exist or belongs to another customer becomes NULL and flagged
			UPDATE t
			SET t.dq_order_issue = 1,
				t.order_id = NULL
			FROM #support_tickets_cleaned AS t
			WHERE t.reject_rule IS NULL AND t.order_id IS NOT NULL 
			AND NOT EXISTS
			(
				SELECT 1
				FROM cln.orders AS o
				WHERE o.order_id = t.order_id AND o.customer_id = t.customer_id
			);

			-- BR-K02: resolved before created, open/escalated with a resolved date
			UPDATE #support_tickets_cleaned
			SET dq_resolution_issue = 1,
				resolved_at = NULL
			WHERE reject_rule IS NULL AND resolved_at IS NOT NULL 
			AND (resolved_at < created_at OR status IN ('Open', 'Escalated'));

			PRINT '========================================================';
			PRINT 'LOADING INTO err.rejected_rows TABLE';
			PRINT '========================================================';
			DELETE FROM err.rejected_rows
			WHERE table_name = 'support_tickets';

			INSERT INTO err.rejected_rows (load_id, table_name, source_row_number, record_key, rule_id, reason)
			SELECT
				load_id, 'support_tickets', source_row_number, ticket_id, reject_rule, reject_reason
			FROM #support_tickets_cleaned
			WHERE reject_rule IS NOT NULL;
			PRINT '========================================================';
			PRINT 'LOADING err.rejected_rows TABLE COMPLETED';
			PRINT '========================================================';

			PRINT '========================================================';
			PRINT 'LOADING INTO cln.support_tickets TABLE ';
			PRINT '========================================================';

			DELETE FROM cln.support_tickets;
			INSERT INTO cln.support_tickets (ticket_id, customer_id, order_id, created_at, resolved_at, category, priority,
				status, channel, satisfaction_score, dq_order_issue, dq_resolution_issue, load_id, source_row_number
			)
			SELECT 
				ticket_id, customer_id, order_id, created_at, resolved_at, category, priority,
				status, channel, satisfaction_score, dq_order_issue, dq_resolution_issue, load_id, source_row_number
			FROM #support_tickets_cleaned
			WHERE reject_rule IS NULL;
			PRINT '========================================================';
			PRINT 'LOADING cln.support_tickets TABLE COMPLETED';
			PRINT '========================================================';
		COMMIT;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK;
		THROW;
	END CATCH
END;
GO
