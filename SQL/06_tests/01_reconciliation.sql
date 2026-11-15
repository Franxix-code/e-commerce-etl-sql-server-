/* =====================================================================
   File     : 01_reconciliation.sql
   Purpose  : Staged rows = clean rows + rejected rows, for all 10 tables.
   Expect   : diff = 0 on every row
   ===================================================================== */

WITH staged AS (
	SELECT 'customers' AS tbl, COUNT(*) AS n FROM stg.customers
	UNION ALL SELECT 'addresses', COUNT(*) AS n FROM stg.addresses
	UNION ALL SELECT 'products', COUNT(*) AS n FROM stg.products
	UNION ALL SELECT 'orders', COUNT(*) AS n FROM stg.orders
	UNION ALL SELECT 'order_items', COUNT(*) AS n FROM stg.order_items
	UNION ALL SELECT 'payments', COUNT(*) AS n FROM stg.payments
	UNION ALL SELECT 'shipments', COUNT(*) AS n FROM stg.shipments
	UNION ALL SELECT 'reviews', COUNT(*) AS n FROM stg.reviews
	UNION ALL SELECT 'returns', COUNT(*) AS n FROM stg.returns
	UNION ALL SELECT 'support_tickets', COUNT(*) AS n FROM stg.support_tickets
),
cleaned AS (
	SELECT 'customers' AS tbl, COUNT(*) AS n FROM cln.customers
	UNION ALL SELECT 'addresses', COUNT(*) AS n FROM cln.addresses
	UNION ALL SELECT 'products', COUNT(*) AS n FROM cln.products
	UNION ALL SELECT 'orders', COUNT(*) AS n FROM cln.orders
	UNION ALL SELECT 'order_items', COUNT(*) AS n FROM cln.order_items
	UNION ALL SELECT 'payments', COUNT(*) AS n FROM cln.payments
	UNION ALL SELECT 'shipments', COUNT(*) AS n FROM cln.shipments
	UNION ALL SELECT 'reviews', COUNT(*) AS n FROM cln.reviews
	UNION ALL SELECT 'returns', COUNT(*) AS n FROM cln.returns
	UNION ALL SELECT 'support_tickets', COUNT(*) AS n FROM cln.support_tickets
),
rejected AS (
	SELECT table_name AS tbl, COUNT(*) AS n FROM err.rejected_rows
	GROUP BY table_name
)

SELECT
	s.tbl AS table_name,
	s.n AS staged,
	c.n AS cleaned,
	ISNULL(r.n, 0) AS rejected,
	s.n - c.n - ISNULL(r.n, 0) AS diff
FROM staged s
JOIN cleaned c
ON c.tbl = s.tbl
LEFT JOIN rejected r
ON r.tbl = s.tbl
ORDER BY s.tbl;
