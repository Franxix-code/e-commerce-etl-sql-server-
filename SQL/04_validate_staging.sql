/* =====================================================================
   File     : 04_validate_staging.sql
   Purpose  : Checks the staging load: loaded rows against expected rows, and rows missing their tracking stamps.
   Expect   : diff = 0 for every table in the first query; unstamped = 0 for every table in the second.
   ===================================================================== */



SELECT 
	t.table_name,
	t.expected_rows,
	t.loaded_rows,
	t.loaded_rows - t.expected_rows AS diff
FROM (
SELECT 
	'customers' AS table_name, 
	123600 AS expected_rows,
	COUNT(*) AS loaded_rows
FROM stg.customers
UNION ALL
SELECT 
	'addresses' AS table_name, 
	151500 AS expected_rows,
	COUNT(*) AS loaded_rows
FROM stg.addresses
UNION ALL
SELECT 
	'orders' AS table_name, 
	202000 AS expected_rows,
	COUNT(*) AS loaded_rows
FROM stg.orders
UNION ALL
SELECT 
	'order_items' AS table_name, 
	388294 AS expected_rows,
	COUNT(*) AS loaded_rows
FROM stg.order_items
UNION ALL
SELECT 
	'products' AS table_name, 
	102000 AS expected_rows,
	COUNT(*) AS loaded_rows
FROM stg.products
UNION ALL
SELECT 
	'payments' AS table_name, 
	205579 AS expected_rows,
	COUNT(*) AS loaded_rows
FROM stg.payments
UNION ALL
SELECT 
	'shipments' AS table_name, 
	163609 AS expected_rows,
	COUNT(*) AS loaded_rows
FROM stg.shipments
UNION ALL
SELECT 
	'reviews' AS table_name, 
	151500 AS expected_rows,
	COUNT(*) AS loaded_rows
FROM stg.reviews
UNION ALL
SELECT 
	'returns' AS table_name, 
	111100 AS expected_rows,
	COUNT(*) AS loaded_rows
FROM stg.returns
UNION ALL
SELECT 
	'support_tickets' AS table_name, 
	111100 AS expected_rows,
	COUNT(*) AS loaded_rows
FROM stg.support_tickets
) AS t;

--------------------------------------------------
SELECT * FROM (
SELECT 
	'customers' AS table_name, 
	COUNT(*) AS unstamped
FROM stg.customers
WHERE load_id IS NULL OR source_file IS NULL
UNION ALL
SELECT 
	'addresses' AS table_name, 
	COUNT(*) AS unstamped
FROM stg.addresses
WHERE load_id IS NULL OR source_file IS NULL
UNION ALL
SELECT 
	'orders' AS table_name, 
	COUNT(*) AS unstamped
FROM stg.orders
WHERE load_id IS NULL OR source_file IS NULL
UNION ALL
SELECT 
	'order_items' AS table_name, 
	COUNT(*) AS unstamped
FROM stg.order_items
WHERE load_id IS NULL OR source_file IS NULL
UNION ALL
SELECT 
	'products' AS table_name, 
	COUNT(*) AS unstamped
FROM stg.products
WHERE load_id IS NULL OR source_file IS NULL
UNION ALL
SELECT 
	'payments' AS table_name, 
	COUNT(*) AS unstamped
FROM stg.payments
WHERE load_id IS NULL OR source_file IS NULL
UNION ALL
SELECT 
	'shipments' AS table_name, 
	COUNT(*) AS unstamped
FROM stg.shipments
WHERE load_id IS NULL OR source_file IS NULL
UNION ALL
SELECT 
	'reviews' AS table_name, 
	COUNT(*) AS unstamped
FROM stg.reviews
WHERE load_id IS NULL OR source_file IS NULL
UNION ALL
SELECT 
	'returns' AS table_name, 
	COUNT(*) AS unstamped
FROM stg.returns
WHERE load_id IS NULL OR source_file IS NULL
UNION ALL
SELECT 
	'support_tickets' AS table_name, 
	COUNT(*) AS unstamped
FROM stg.support_tickets
WHERE load_id IS NULL OR source_file IS NULL
) AS t;
