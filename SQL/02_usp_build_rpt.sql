/* =====================================================================
   File     : 02_usp_build_rpt.sql
   Purpose  : Rebuilds all reporting tables from the clean layer in one transaction.
   KPI rules: revenue = Delivered orders using total_amount_calc | payment success = Success / (Success + Failed)
               return rate = returned items / items sold on Delivered or Returned orders | repeat customer = 2 or more Delivered orders
   ===================================================================== */

CREATE OR ALTER PROCEDURE etl.usp_build_rpt
AS
BEGIN 
	SET NOCOUNT ON;
	SET XACT_ABORT ON;
	BEGIN TRY
		BEGIN TRAN;
			-- helper 1: refunds per order (Approved or refunded returns)
			DROP TABLE IF EXISTS #order_refunds;

			SELECT 
				oi.order_id,
				SUM(r.refund_amount) refund_amount
			INTO #order_refunds
			FROM cln.returns r
			JOIN cln.order_items oi
			ON oi.order_item_id = r.order_item_id
			WHERE r.return_status IN ('Approved', 'Refunded') AND r.refund_amount IS NOT NULL
			GROUP BY oi.order_id;

			CREATE UNIQUE INDEX ix_order_refunds ON #order_refunds (order_id);

			-- helper 2: units and revenue per product, for delivered orders only
			DROP TABLE IF EXISTS #product_sales;

			SELECT 
				oi.product_id, 
				SUM(oi.quantity) units_sold,
				SUM(oi.line_total) revenue
			INTO #product_sales
			FROM cln.order_items oi
			JOIN cln.orders o
			ON o.order_id = oi.order_id
			WHERE  o.order_status = 'Delivered'
			GROUP BY oi.product_id;

			CREATE UNIQUE INDEX ix_product_sales ON #product_sales (product_id);

			--------------------------------------------------------------------------
			--- KPI 1: Monthly revenue by country and channel
			--------------------------------------------------------------------------
			DELETE FROM rpt.monthly_revenue;

			INSERT INTO rpt.monthly_revenue (order_month, country, channel, order_count, gross_revenue, avg_order_value)
			SELECT 
				DATEFROMPARTS(YEAR(o.order_date), MONTH(o.order_date), 1),
				ISNULL(c.country, 'Unknown'),
				ISNULL(o.channel, 'Unknown'),
				COUNT(*),
				SUM(o.total_amount_calc),
				AVG(o.total_amount_calc)
			FROM cln.orders o
			JOIN cln.customers c
			ON c.customer_id = o.customer_id
			WHERE o.order_status = 'Delivered' AND o.total_amount_calc IS NOT NULL
			GROUP BY	DATEFROMPARTS(YEAR(o.order_date), MONTH(o.order_date), 1),
						ISNULL(c.country, 'Unknown'),
						ISNULL(o.channel, 'Unknown');

			-------------------------------------------------------------------------
			--- KPI 2: Average order value and items per order, by month revenue
			-------------------------------------------------------------------------
			DELETE FROM rpt.order_value_monthly;

			WITH per_order AS (
				SELECT 
					order_id,
					COUNT(*) items,
					SUM(quantity) units
				FROM cln.order_items
				GROUP BY order_id
			)
			INSERT INTO rpt.order_value_monthly (order_month, order_count, avg_order_value, avg_items_per_order, avg_units_per_order)
			SELECT
				DATEFROMPARTS(YEAR(o.order_date), MONTH(o.order_date), 1),
				COUNT(*),
				AVG(o.total_amount_calc),
				AVG(CAST(p.items AS DECIMAL(10, 2))),
				AVG(CAST(p.units AS DECIMAL(10, 2)))
			FROM cln.orders o
			JOIN per_order p
			ON o.order_id = p.order_id
			WHERE o.order_status = 'Delivered' AND o.total_amount_calc IS NOT NULL
			GROUP BY DATEFROMPARTS(YEAR(o.order_date), MONTH(o.order_date), 1);

			-------------------------------------------------------------------------
			--- KPI 3: Top products and categories by revenue 
			-------------------------------------------------------------------------
			DELETE FROM rpt.product_revenue;

			INSERT INTO rpt.product_revenue (product_id, product_name, category, brand, units_sold, revenue, revenue_rank, category_rank)
			SELECT 
				s.product_id,
				p.product_name,
				ISNULL(p.category, 'Unknown'),
				p.brand,
				s.units_sold,
				s.revenue,
				RANK() OVER (ORDER BY s.revenue DESC),
				RANK() OVER (PARTITION BY ISNULL(p.category, 'Unknown') ORDER BY s.revenue DESC)
			FROM #product_sales s
			JOIN cln.products p
			ON s.product_id = p.product_id;

			DELETE FROM rpt.category_revenue;

			INSERT INTO rpt.category_revenue (category, product_sold, units_sold, revenue, revenue_share_pct)
			SELECT
				ISNULL(p.category, 'Unknown'),
				COUNT(*),
				SUM(s.units_sold),
				SUM(s.revenue),
				CAST(100.0 * SUM(s.revenue) / SUM(SUM(s.revenue)) OVER () AS DECIMAL(5, 2))
			FROM #product_sales s
			JOIN cln.products p
			ON p.product_id = s.product_id
			GROUP BY ISNULL(p.category, 'Unknown');

			-------------------------------------------------------------------------
			--- KPI 4: payment success rate by method 
			-------------------------------------------------------------------------
			DELETE FROM rpt.payment_success_by_method;

			INSERT INTO rpt.payment_success_by_method (payment_method, total_payments, successful, failed, pending, refunded, success_rate_pct, successful_amount)
			SELECT 
				ISNULL(payment_method, 'Unknown'),
				COUNT(*),
				SUM(CASE WHEN payment_status = 'Success' THEN 1 ELSE 0 END),
				SUM(CASE WHEN payment_status = 'Failed' THEN 1 ELSE 0 END),
				SUM(CASE WHEN payment_status = 'Pending' THEN 1 ELSE 0 END),
				SUM(CASE WHEN payment_status = 'Refunded' THEN 1 ELSE 0 END),
				CAST(100.0 * SUM(CASE WHEN payment_status = 'Success' THEN 1 ELSE 0 END) / NULLIF(SUM(CASE WHEN payment_status IN ('Success', 'Failed') THEN 1 ELSE 0 END), 0) AS DECIMAL(5,2)), 
				SUM(CASE WHEN payment_status = 'Success' THEN ISNULL(amount, 0) ELSE 0 END)
			FROM cln.payments
			GROUP BY ISNULL(payment_method, 'Unknown');

			-------------------------------------------------------------------------
			--- KPI 5: delivery time by carrier 
			-------------------------------------------------------------------------
			DELETE FROM rpt.delivery_by_carrier;

			INSERT INTO rpt.delivery_by_carrier (carrier, shipments, delivered_shipments, avg_days_to_ship, avg_days_to_transit, avg_days_order_to_delivery)
			SELECT 
				ISNULL(s.carrier, 'Unknown'),
				COUNT(*),
				SUM(CASE WHEN s.delivery_date IS NOT NULL THEN 1 ELSE 0 END),
				AVG(CAST(CASE WHEN s.ship_date IS NOT NULL THEN DATEDIFF(DAY, o.order_date, s.ship_date) END AS DECIMAL(10, 2))),
				AVG(CAST(CASE WHEN s.ship_date IS NOT NULL AND s.delivery_date IS NOT NULL THEN DATEDIFF(DAY, s.ship_date, s.delivery_date) END AS DECIMAL(10, 2))),
				AVG(CAST(CASE WHEN s.delivery_date IS NOT NULL THEN DATEDIFF(DAY, o.order_date, s.delivery_date) END AS DECIMAL(10, 2)))
			FROM cln.shipments s
			JOIN cln.orders o
			ON o.order_id = s.order_id
			GROUP BY ISNULL(s.carrier, 'Unknown');

			-------------------------------------------------------------------------
			--- KPI 6: return rate by category, and top return reasons 
			-------------------------------------------------------------------------
			DELETE FROM rpt.return_rate_by_category;

			WITH sold AS (
				SELECT 
					ISNULL(p.category, 'Unknown') category,
					COUNT(*) items_sold
				FROM cln.order_items oi
				JOIN cln.orders o
				ON o.order_id = oi.order_id AND o.order_status IN ('Delivered', 'Returned')
				JOIN cln.products p
				ON p.product_id = oi.product_id
				GROUP BY ISNULL(p.category, 'Unknown')
			),
			returned AS (
				SELECT
					ISNULL(p.category, 'Unknown') category,
					COUNT(DISTINCT r.order_item_id) items_returned,
					SUM(
						CASE 
							WHEN r.return_status IN ('Approved', 'Refunded') THEN ISNULL(r.refund_amount, 0)
							ELSE 0
						END
					) refunded_amount
				FROM cln.returns r
				JOIN cln.order_items oi
				ON oi.order_item_id = r.order_item_id
				JOIN cln.products p
				ON oi.product_id = p.product_id
				GROUP BY ISNULL(p.category, 'Unknown')
			)
			INSERT INTO rpt.return_rate_by_category (category, items_sold, items_returned, return_rate_pct, refunded_amount)
			SELECT
				s.category,
				s.items_sold,
				ISNULL(r.items_returned, 0),
				CAST(100.0 * ISNULL(r.items_returned, 0) / s.items_sold AS DECIMAL(5, 2)),
				ISNULL(r.refunded_amount, 0)
			FROM sold s
			LEFT JOIN returned r
			ON s.category = r.category;

			DELETE FROM rpt.return_reasons;
			INSERT INTO rpt.return_reasons (reason, return_count, share_pct, refunded_amount,reason_rank)
			SELECT
				ISNULL(reason, 'Unknown'),
				COUNT(*),
				CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5, 2)),
				SUM(
						CASE 
							WHEN return_status IN ('Approved', 'Refunded') THEN ISNULL(refund_amount, 0)
							ELSE 0
						END
					),
					RANK() OVER (ORDER BY COUNT(*) DESC)
			FROM cln.returns
			GROUP BY ISNULL(reason, 'Unknown');
			-------------------------------------------------------------------------
			--- KPI 7: average review rating by product and by category 
			-------------------------------------------------------------------------
			DELETE FROM rpt.product_ratings;

			INSERT INTO rpt.product_ratings (product_id, product_name, category, review_count, avg_rating)
			SELECT
				r.product_id,
				p.product_name,
				ISNULL(p.category, 'Unknown'),
				COUNT(r.rating),
				CAST(AVG(CAST(r.rating AS DECIMAL(4, 2))) AS DECIMAL(3, 2))
			FROM cln.reviews r
			JOIN cln.products p
			ON r.product_id = p.product_id
			WHERE r.rating IS NOT NULL
			GROUP BY r.product_id, p.product_name, ISNULL(p.category, 'Unknown');

			DELETE FROM rpt.category_ratings;

			INSERT INTO rpt.category_ratings (category, review_count, avg_rating)
			SELECT
				ISNULL(p.category, 'Unknown'),
				COUNT(r.rating),
				CAST(AVG(CAST(r.rating AS DECIMAL(4, 2))) AS DECIMAL(3, 2))
			FROM cln.reviews r
			JOIN cln.products p
			ON p.product_id = r.product_id
			WHERE r.rating IS NOT NULL
			GROUP BY ISNULL(p.category, 'Unknown');

			-------------------------------------------------------------------------
			--- KPI 8: ticket volume and resolution time by category  
			-------------------------------------------------------------------------
			DELETE FROM rpt.ticket_statistics;

			INSERT INTO rpt.ticket_statistics (category, ticket_count, open_tickets, resolved_tickets, avg_resolution_days, avg_satisfaction)
			SELECT
				ISNULL(category, 'Unknown'),
				COUNT(*),
				SUM(CASE WHEN status IN ('Open', 'Escalated') THEN 1 ELSE 0 END),
				SUM(CASE WHEN resolved_at IS NOT NULL THEN 1 ELSE 0 END),
				AVG(CAST(CASE WHEN resolved_at IS NOT NULL THEN DATEDIFF(DAY, created_at, resolved_at) END AS DECIMAL(10, 2))),
				AVG(CAST(satisfaction_score AS DECIMAL(4, 2)))
			FROM cln.support_tickets
			GROUP BY ISNULL(category, 'Unknown');

			-------------------------------------------------------------------------
			--- KPI 9: customer segmentation and lifetime value 
			-------------------------------------------------------------------------
			DELETE FROM rpt.customer_ltv;

			WITH delivered AS (
				SELECT 
					o.customer_id,
					COUNT(*) delivered_orders,
					MIN(o.order_date) first_order_date,
					MAX(o.order_date) last_order_date,
					SUM(o.total_amount_calc) lifetime_value,
					SUM(ISNULL(f.refund_amount, 0)) refunds
				FROM cln.orders o
				LEFT JOIN #order_refunds f
				ON f.order_id = o.order_id
				WHERE o.order_status = 'Delivered' AND o.total_amount_calc IS NOT NULL
				GROUP BY o.customer_id
			)
			INSERT INTO rpt.customer_ltv (customer_id, country, loyalty_tier, delivered_orders, first_order_date, last_order_date, lifetime_value, refunds, net_lifetime_value, avg_order_value, segment)
			SELECT 
				c.customer_id,
				ISNULL(c.country, 'Unknown'),
				c.loyalty_tier,
				ISNULL(d.delivered_orders, 0),
				d.first_order_date,
				d.last_order_date,
				ISNULL(d.lifetime_value, 0),
				ISNULL(d.refunds, 0),
				ISNULL(d.lifetime_value, 0) - ISNULL(d.refunds, 0),
				CASE WHEN d.delivered_orders > 0 THEN d.lifetime_value / d.delivered_orders END,
				CASE
					WHEN ISNULL(d.delivered_orders, 0) = 0 THEN 'No orders'
					WHEN ISNULL(d.delivered_orders, 0) = 1 THEN 'One-time'
					ELSE 'Repeat'
				END 
			FROM cln.customers c
			LEFT JOIN delivered d
			ON d.customer_id = c.customer_id;

			DELETE FROM rpt.customer_segment_summary;

			INSERT INTO rpt.customer_segment_summary (segment, customer_count, total_lifetime_value, avg_lifetime_value, pct_of_customers, pct_of_revenue)
			SELECT
				segment,
				COUNT(*),
				SUM(lifetime_value),
				AVG(lifetime_value),
				CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS DECIMAL(5,2)),
				CAST(100.0 * SUM(lifetime_value) / NULLIF(SUM(SUM(lifetime_value)) OVER (), 0) AS DECIMAL(5, 2))
			FROM rpt.customer_ltv
			GROUP BY segment;
		COMMIT;
	END TRY
	BEGIN CATCH
		IF @@TRANCOUNT > 0 ROLLBACK;
		THROW;
	END CATCH
END;
GO
