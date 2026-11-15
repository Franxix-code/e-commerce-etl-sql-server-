/* =====================================================================
   File     : 03_rerun_snapshot.sql
   Purpose  : Rerun test: snapshot of counts, key checksums, money totals and reject counts, to compare two pipeline runs.
   Expect   : 0 differences between two runs of the same code
   ===================================================================== */

IF OBJECT_ID('etl.rerun_snapshot', 'U') IS NULL
CREATE TABLE etl.rerun_snapshot (
	run_label NVARCHAR(20) NOT NULL,
	metric NVARCHAR(80) NOT NULL,
	metric_value DECIMAL(38, 2),
	PRIMARY KEY (run_label, metric)
);
GO

CREATE OR ALTER PROCEDURE etl.usp_take_snapshot @label NVARCHAR(20)
AS
BEGIN
	SET NOCOUNT ON;
	DELETE FROM etl.rerun_snapshot WHERE run_label = @label;

	INSERT INTO etl.rerun_snapshot (run_label, metric, metric_value)
	-- run counts
	SELECT @label, 'customers.rows',			COUNT(*) FROM cln.customers UNION ALL
	SELECT @label, 'addresses.rows',			COUNT(*) FROM cln.addresses UNION ALL
	SELECT @label, 'products.rows',				COUNT(*) FROM cln.products UNION ALL
	SELECT @label, 'orders.rows',				COUNT(*) FROM cln.orders UNION ALL
	SELECT @label, 'order_items.rows',			COUNT(*) FROM cln.order_items UNION ALL
	SELECT @label, 'payments.rows',				COUNT(*) FROM cln.payments UNION ALL
	SELECT @label, 'shipments.rows',			COUNT(*) FROM cln.shipments UNION ALL
	SELECT @label, 'reviews.rows',				COUNT(*) FROM cln.reviews UNION ALL
	SELECT @label, 'returns.rows',				COUNT(*) FROM cln.returns UNION ALL
	SELECT @label, 'support_tickets.rows',		COUNT(*) FROM cln.support_tickets UNION ALL

	-- key checksums (catch a different set of rows even when the counts match)
	SELECT @label, 'customers.keys',			CHECKSUM_AGG(CHECKSUM(customer_id))		FROM cln.customers UNION ALL
	SELECT @label, 'addresses.keys',			CHECKSUM_AGG(CHECKSUM(address_id))		FROM cln.addresses UNION ALL
	SELECT @label, 'products.keys',				CHECKSUM_AGG(CHECKSUM(product_id))		FROM cln.products UNION ALL
	SELECT @label, 'orders.keys',				CHECKSUM_AGG(CHECKSUM(order_id))		FROM cln.orders UNION ALL
	SELECT @label, 'order_items.keys',			CHECKSUM_AGG(CHECKSUM(order_item_id))	FROM cln.order_items UNION ALL
	SELECT @label, 'payments.keys',				CHECKSUM_AGG(CHECKSUM(payment_id))		FROM cln.payments UNION ALL
	SELECT @label, 'shipments.keys',			CHECKSUM_AGG(CHECKSUM(shipment_id))		FROM cln.shipments UNION ALL
	SELECT @label, 'reviews.keys',				CHECKSUM_AGG(CHECKSUM(review_id))		FROM cln.reviews UNION ALL
	SELECT @label, 'returns.keys',				CHECKSUM_AGG(CHECKSUM(return_id))		FROM cln.returns UNION ALL
	SELECT @label, 'support_tickets.keys',		CHECKSUM_AGG(CHECKSUM(ticket_id))		FROM cln.support_tickets UNION ALL

	-- money totals
	SELECT @label, 'products.sum_unit_price',		SUM(ISNULL(unit_price, 0)) FROM cln.products UNION ALL
	SELECT @label, 'orders.sum_total_calc',			SUM(ISNULL(total_amount_calc, 0)) FROM cln.orders UNION ALL
	SELECT @label, 'order_items.sum_line_total',	SUM(ISNULL(line_total, 0)) FROM cln.order_items UNION ALL	
	SELECT @label, 'payments.sum_amount',			SUM(ISNULL(amount, 0)) FROM cln.payments UNION ALL
	SELECT @label, 'shipments.sum_cost',			SUM(ISNULL(shipping_cost, 0)) FROM cln.shipments UNION ALL
	SELECT @label, 'returns.sum_refund',		SUM(ISNULL(refund_amount, 0)) FROM cln.returns UNION ALL
	
	-- report stats
	SELECT @label, 'rpt.monthly_revenue_gross',		SUM(gross_revenue) FROM rpt.monthly_revenue UNION ALL
	SELECT @label, 'rpt.monthly_revenue.rows',		COUNT(*) FROM rpt.monthly_revenue UNION ALL
	SELECT @label, 'rpt.product_revenue.rows',		COUNT(*) FROM rpt.product_revenue UNION ALL
	SELECT @label, 'rpt.customer_ltv.value',		SUM(lifetime_value) FROM rpt.customer_ltv UNION ALL
	SELECT @label, 'rpt.return_reasons.rows',		COUNT(*) FROM rpt.return_reasons UNION ALL
	-- rejected rows per table and rule
	SELECT 
		@label, 
		'rejected.' + table_name + '.' + rule_id, 
		COUNT (*) FROM err.rejected_rows 
	GROUP BY table_name, rule_id;
END;
GO

-- USAGE (rerun test)
--   EXEC etl.usp_take_snapshot 'run1';
--   ... run the whole pipeline again ...
--   EXEC etl.usp_take_snapshot 'run2';
--

