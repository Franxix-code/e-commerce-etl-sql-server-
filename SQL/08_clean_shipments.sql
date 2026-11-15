/* =====================================================================
   File     : 08_clean_shipments.sql
   Purpose  : Cleans stg.shipments and loads cln.shipments (rules BR-S01 to BR-S06).
   Needs    : cln.orders loaded (foreign key)
   ===================================================================== */

CREATE OR ALTER PROCEDURE etl.usp_load_cln_shipments
AS
BEGIN 
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	BEGIN TRY
		BEGIN TRAN;
			DROP TABLE IF EXISTS #shipments_cleaned;
			SELECT 
				CASE
					WHEN UPPER(TRIM(shipment_id)) IN ('', '-', 'NA', 'NULL', 'NONE', 'N/A') THEN NULL
					WHEN UPPER(TRIM(shipment_id)) LIKE 'SHIP[0-9]%' THEN 'SHIP-' + SUBSTRING(UPPER(TRIM(shipment_id)), 5, LEN(UPPER(TRIM(shipment_id))))
					ELSE UPPER(TRIM(shipment_id))
				END AS shipment_id,
				CASE
					WHEN UPPER(TRIM(order_id)) IN ('', '-', 'NA', 'NULL', 'NONE', 'N/A') THEN NULL
					WHEN UPPER(TRIM(order_id)) LIKE 'ORD[0-9]%' THEN 'ORD-' + SUBSTRING(UPPER(TRIM(order_id)), 4, LEN(UPPER(TRIM(order_id))))
					ELSE UPPER(TRIM(order_id))
				END AS order_id,
				CASE
					WHEN UPPER(TRIM(carrier)) LIKE '%FED%' THEN 'FedEx'
					WHEN UPPER(TRIM(carrier)) LIKE '%GIG%' THEN 'GIG Logistics'
					WHEN UPPER(TRIM(carrier)) LIKE '%KWIK%' THEN 'Kwik Delivery'
					WHEN UPPER(TRIM(carrier)) IN ('LOCAL', 'LOCAL COURIER', 'DISPATCH RIDER') THEN 'Local Courier'
					WHEN UPPER(TRIM(carrier)) LIKE '%DHL%' THEN 'DHL'
					WHEN UPPER(TRIM(carrier)) = 'SENDBOX' THEN 'Sendbox'
					ELSE NULL
				END AS carrier,
				CASE	
					WHEN UPPER(TRIM(tracking_number)) IN ('', '-', 'NONE', 'NULL', 'N/A', 'NA') THEN NULL
					ELSE UPPER(TRIM(tracking_number))
				END AS tracking_number,
				CASE
					WHEN TRIM(ship_date) LIKE '[0-9][0-9][0-9][0-9]/[0-9][0-9]/[0-9][0-9]' 
					THEN TRY_CONVERT(DATE, REPLACE(TRIM(ship_date), '/', '-'), 23)						-- 2024/03/05
					WHEN TRIM(ship_date) LIKE '[0-9][0-9]/[0-9][0-9]/[0-9][0-9][0-9][0-9]' 
					THEN TRY_CONVERT(DATE, TRIM(ship_date), 103)											-- 05/03/2023 (day first)
					WHEN TRIM(ship_date) LIKE '[0-9][0-9].[0-9][0-9].[0-9][0-9][0-9][0-9]' 
					THEN TRY_CONVERT(DATE, REPLACE(TRIM(ship_date), '.', '-'), 104)						-- 05.03.2023 (day first)
					WHEN TRIM(ship_date) LIKE '[0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9]' 
					THEN TRY_CONVERT(DATE, TRIM(ship_date), 110)											-- 03-05-2023 (month first)
					WHEN TRIM(ship_date) LIKE '[0-9][0-9]-[0-9][0-9]-[0-9][0-9]' 
					THEN TRY_CONVERT(DATE, TRIM(ship_date), 5)											-- 03-05-2023 (day first)
					WHEN TRIM(ship_date) LIKE '[0-9][0-9] [A-Za-z][A-Za-z][A-Za-z] [0-9][0-9][0-9][0-9]' 
					THEN TRY_CONVERT(DATE, TRIM(ship_date), 106)											-- 05 Mar 2023 
					WHEN TRIM(ship_date) LIKE '[A-Za-z]%[0-9][0-9], [0-9][0-9][0-9][0-9]' 
					THEN TRY_CONVERT(DATE, TRIM(ship_date), 107)											-- March 05, 2023 
					WHEN TRIM(ship_date) LIKE '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]%'
					THEN TRY_CONVERT(DATE, LEFT(TRIM(ship_date), 10), 23)								-- 2023-03-05 00:00:00
				END AS ship_date,
				CASE
					WHEN TRIM(delivery_date) LIKE '[0-9][0-9][0-9][0-9]/[0-9][0-9]/[0-9][0-9]' 
					THEN TRY_CONVERT(DATE, REPLACE(TRIM(delivery_date), '/', '-'), 23)						-- 2024/03/05
					WHEN TRIM(delivery_date) LIKE '[0-9][0-9]/[0-9][0-9]/[0-9][0-9][0-9][0-9]' 
					THEN TRY_CONVERT(DATE, TRIM(delivery_date), 103)											-- 05/03/2023 (day first)
					WHEN TRIM(delivery_date) LIKE '[0-9][0-9].[0-9][0-9].[0-9][0-9][0-9][0-9]' 
					THEN TRY_CONVERT(DATE, REPLACE(TRIM(delivery_date), '.', '-'), 104)						-- 05.03.2023 (day first)
					WHEN TRIM(delivery_date) LIKE '[0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9]' 
					THEN TRY_CONVERT(DATE, TRIM(delivery_date), 110)											-- 03-05-2023 (month first)
					WHEN TRIM(delivery_date) LIKE '[0-9][0-9]-[0-9][0-9]-[0-9][0-9]' 
					THEN TRY_CONVERT(DATE, TRIM(delivery_date), 5)											-- 03-05-2023 (day first)
					WHEN TRIM(delivery_date) LIKE '[0-9][0-9] [A-Za-z][A-Za-z][A-Za-z] [0-9][0-9][0-9][0-9]' 
					THEN TRY_CONVERT(DATE, TRIM(delivery_date), 106)											-- 05 Mar 2023 
					WHEN TRIM(delivery_date) LIKE '[A-Za-z]%[0-9][0-9], [0-9][0-9][0-9][0-9]' 
					THEN TRY_CONVERT(DATE, TRIM(delivery_date), 107)											-- March 05, 2023 
					WHEN TRIM(delivery_date) LIKE '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]%'
					THEN TRY_CONVERT(DATE, LEFT(TRIM(delivery_date), 10), 23)								-- 2023-03-05 00:00:00
				END AS delivery_date,
				CASE
					WHEN UPPER(TRIM(shipment_status)) IN ('DELIVERED', 'COMPLETED', 'COMPLETE') THEN 'Delivered'
					WHEN UPPER(TRIM(shipment_status)) IN ('RETURNED', 'RTO', 'RETURNED TO SENDER') THEN 'Returned'
					WHEN UPPER(TRIM(shipment_status)) IN ('IN TRANSIT', 'IN_TRANSIT', 'SHIPPED') THEN 'In Transit'
					ELSE NULL
				END AS shipment_status,
				TRY_CAST(NULLIF(TRIM(REPLACE(REPLACE(REPLACE(UPPER(shipping_cost), 'NGN', ''), 'N', ''), ',', '')), '') AS DECIMAL(10, 2)) AS shipping_cost,
				CASE
					WHEN UPPER(TRIM(weight_kg)) LIKE '%KG' THEN TRY_CAST(REPLACE(UPPER(TRIM(weight_kg)), 'KG', '') AS DECIMAL(8,2))
					WHEN UPPER(TRIM(weight_kg)) LIKE '%G' THEN TRY_CAST(REPLACE(UPPER(TRIM(weight_kg)), 'G', '') AS DECIMAL(8,2)) / 1000
					ELSE TRY_CAST(UPPER(TRIM(weight_kg)) AS DECIMAL(8,2))
				END AS weight_kg,
				load_id,
				source_row_number,
				ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(shipment_id)) ORDER BY source_row_number) AS rn
			INTO #shipments_cleaned
			FROM stg.shipments;

			ALTER TABLE #shipments_cleaned
			ADD reject_rule NVARCHAR(50) NULL,
				reject_reason NVARCHAR(100) NULL,
				dq_tracking_issue NVARCHAR(20) NULL,
				dq_delivery_before_ship BIT NOT NULL DEFAULT 0,
				dq_status_conflict BIT NOT NULL DEFAULT 0;

			CREATE INDEX ix_ship_order ON #shipments_cleaned (order_id);

			--- REJECTS -----
			-- BR-S06: Duplicate shipment_id
			UPDATE #shipments_cleaned
			SET reject_rule = 'BR-S06',
				reject_reason = 'Duplicate shipment_id, first row in file was kept'
			WHERE rn > 1;

			-- BR-S01: Orders not found in cln.orders table
			UPDATE s
			SET reject_rule = 'BR-S01',
				reject_reason = 'orders not found in cln.orders'
			FROM #shipments_cleaned s
			WHERE s.reject_rule IS NULL AND NOT EXISTS 
			(
				SELECT 1
				FROM cln.orders o
				WHERE o.order_id = s.order_id
			);

			-- BR-S04: Shipping cost is negative
			UPDATE #shipments_cleaned
			SET reject_rule = 'BR-S04',
				reject_reason = 'negative shipment cost'
			WHERE reject_rule IS NULL AND shipping_cost < 0;

			-----FLAGS----
			-- BR-S02: delivery date before shipping date becomes null and flagged
			UPDATE #shipments_cleaned
			SET dq_delivery_before_ship = 1,
				delivery_date = NULL
			WHERE reject_rule IS NULL AND delivery_date < ship_date;

			-- BR-S05: tracking number shared by more than one shipment
			UPDATE #shipments_cleaned
			SET dq_tracking_issue = 'Duplicate'
			WHERE reject_rule IS NULL AND tracking_number IN 
			(
				SELECT tracking_number
				FROM #shipments_cleaned
				WHERE reject_rule IS NULL AND tracking_number IS NOT NULL
				GROUP BY tracking_number
				HAVING COUNT(*) > 1
			);

			-- BR-S01: the order status should be delivered, shipped or returned
			UPDATE s
			SET dq_status_conflict = 1
			FROM #shipments_cleaned s
			JOIN cln.orders o
			ON o.order_id = s.order_id
			WHERE reject_rule IS NULL AND o.order_status NOT IN ('Delivered', 'Shipped', 'Returned');


			PRINT '========================================================';
			PRINT 'LOADING INTO err.rejected_rows TABLE';
			PRINT '========================================================';
			DELETE FROM err.rejected_rows WHERE table_name = 'shipments';
			INSERT INTO err.rejected_rows (load_id, table_name, source_row_number, record_key, rule_id,reason)
			SELECT
				load_id, 'shipments', source_row_number, shipment_id, reject_rule, reject_reason
			FROM #shipments_cleaned
			WHERE reject_rule IS NOT NULL;
			PRINT '========================================================';
			PRINT 'LOADING err.rejected_rows TABLE COMPLETED';
			PRINT '========================================================';	

			PRINT '========================================================';
			PRINT 'LOADING INTO cln.shipments TABLE';
			PRINT '========================================================';
			DELETE FROM cln.shipments;
			INSERT INTO cln.shipments (shipment_id, order_id, carrier, tracking_number, ship_date, delivery_date,
				shipment_status, shipping_cost, weight_kg, dq_tracking_issue, dq_delivery_before_ship,dq_status_conflict,
				load_id, source_row_number
			)
			SELECT
				shipment_id, order_id, carrier, tracking_number, ship_date, delivery_date,
				shipment_status, shipping_cost, weight_kg, dq_tracking_issue, dq_delivery_before_ship,dq_status_conflict,
				load_id, source_row_number
			FROM #shipments_cleaned
			WHERE reject_rule IS NULL;
			PRINT '========================================================';
			PRINT 'LOADING cln.shipments TABLE COMPLETED';
			PRINT '========================================================';
		COMMIT;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK;
		THROW;
	END CATCH
END;
GO
