/* =====================================================================
   File     : 02_acceptance_checks.sql
   Purpose  : Acceptance criteria 3, 5, 6, 7 and 8 of the specification (section 10).
   Note     : criteria 1, 2 and 4 are covered by 01_reconciliation.sql, the constraints and 03_rerun_snapshot.sql
   ===================================================================== */

-- criterion 3: items total match order totals (the two numbers must be equal)
SELECT 
(SELECT SUM(line_total) FROM cln.order_items) items_total,
(SELECT SUM(total_amount_calc) FROM cln.orders) orders_calc_total;

-- criterion 4 :
SELECT COALESCE(a.metric, b.metric) AS metric, a.metric_value AS run1, b.metric_value AS run2,
       CASE WHEN a.metric IS NULL THEN 'only in run2' WHEN b.metric IS NULL THEN 'only in run1' ELSE 'value changed' END AS what
FROM (SELECT * FROM etl.rerun_snapshot WHERE run_label = 'run1') AS a
FULL JOIN (SELECT * FROM etl.rerun_snapshot WHERE run_label = 'run2') AS b ON a.metric = b.metric
WHERE a.metric IS NULL OR b.metric IS NULL OR ISNULL(a.metric_value, -1) <> ISNULL(b.metric_value, -1);   -- must return 0 rows

-- guard against a false pass: no clean table may be empty (must return 0 rows)
SELECT metric FROM etl.rerun_snapshot WHERE run_label = 'run2' AND metric LIKE '%.rows' AND ISNULL(metric_value, 0) = 0;

-- criterion 5: every rejected row has a rule (first must return 0, the list should match the rule catalogue)
SELECT COUNT(*) FROM err.rejected_rows WHERE rule_id IS NULL OR rule_id = '';
SELECT DISTINCT table_name, rule_id FROM err.rejected_rows ORDER BY table_name, rule_id;

-- criterion 6: the run log shows each run with its status
SELECT TOP(5) * FROM etl.run_log ORDER BY load_id DESC;

-- criterion 7: look at 20 random rows per table, raw next to clean
SELECT TOP (20) s.customer_id raw_id, s.email raw_email, s.signup_date raw_date,
				c.customer_id, c.email, c.signup_date
FROM cln.customers c
JOIN stg.customers s
ON c.source_row_number = s.source_row_number
ORDER BY NEWID();


---------------------------------------------------------
---- Criterion 8: every report total equals its source (all diff values must be 0)
-----------------------------------------------------------
WITH delivered_revenue AS (
	SELECT
		SUM(total_amount_calc) revenue,
		COUNT(*) order_count
	FROM cln.orders
	WHERE order_status = 'Delivered' AND total_amount_calc IS NOT NULL
),
delivered_items AS (
	SELECT SUM(oi.line_total) revenue
	FROM cln.order_items oi
	JOIN cln.orders o
	ON o.order_id = oi.order_id
	WHERE o.order_status = 'Delivered'
),
checks AS (
	SELECT 
		'monthly_revenue: gross revenue' AS metric,
		CAST((SELECT SUM(gross_revenue) FROM rpt.monthly_revenue) AS DECIMAL(18, 2)) report_value,
		CAST((SELECT revenue FROM delivered_revenue) AS DECIMAL(18, 2)) source_value
	UNION ALL
	SELECT 
		'monthly_revenue: order count',
		(SELECT SUM(order_count) FROM rpt.monthly_revenue),
		(SELECT order_count FROM delivered_revenue)
	UNION ALL
	SELECT 
		'order_value_monthly: order count',
		(SELECT SUM(order_count) FROM rpt.order_value_monthly),
		(SELECT order_count FROM delivered_revenue)
	UNION ALL
	SELECT
		'product_revenue: revenue',
		(SELECT SUM(revenue) FROM rpt.product_revenue),
		(SELECT revenue FROM delivered_items)
	UNION ALL
	SELECT 
		'category_revenue: revenue',
		(SELECT SUM(revenue) FROM rpt.category_revenue),
		(SELECT revenue FROM delivered_items)
	UNION ALL
	SELECT 
		'payment_success_by_method: payments',
		(SELECT SUM(total_payments) FROM rpt.payment_success_by_method),
		(SELECT COUNT(*) FROM cln.payments)
	UNION ALL 
	SELECT 
		'delivery_by_carrier: shipments',
		(SELECT SUM(shipments) FROM rpt.delivery_by_carrier),
		(SELECT COUNT(*) FROM cln.shipments)
	UNION ALL
	SELECT 
		'return_rate_by_category: returned items',
		(SELECT SUM(items_returned) FROM rpt.return_rate_by_category),
		(SELECT COUNT(DISTINCT order_item_id) FROM cln.returns)
	UNION ALL
	SELECT 
		'return_reasons: returns',
		(SELECT SUM(return_count) FROM rpt.return_reasons),
		(SELECT COUNT(*) FROM cln.returns)
	UNION ALL
	SELECT 
		'product_ratings: rated reviews',
		(SELECT SUM(review_count) FROM rpt.product_ratings),
		(SELECT COUNT(rating) FROM cln.reviews)
	UNION ALL
	SELECT 
		'category_ratings: rated reviews',
		(SELECT SUM(review_count) FROM rpt.category_ratings),
		(SELECT COUNT(rating) FROM cln.reviews)
	UNION ALL
	SELECT 
		'ticket_statistics: tickets',
		(SELECT SUM(ticket_count) FROM rpt.ticket_statistics),
		(SELECT COUNT(*) FROM cln.support_tickets)
	UNION ALL
	SELECT 
		'customer_ltv: customers',
		(SELECT COUNT(*) FROM rpt.customer_ltv),
		(SELECT COUNT(*) FROM cln.customers)
	UNION ALL
	SELECT 
		'customer_ltv: lifetime value',
		(SELECT SUM(lifetime_value) FROM rpt.customer_ltv),
		(SELECT revenue FROM delivered_revenue)
	UNION ALL
	SELECT 
		'customer_segment_summary: customers',
		(SELECT SUM(customer_count) FROM rpt.customer_segment_summary),
		(SELECT COUNT(*) FROM cln.customers)
)
SELECT metric, report_value, source_value, report_value - source_value AS diff
FROM checks;
