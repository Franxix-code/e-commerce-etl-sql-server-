/* =====================================================================
   File     : 02_create_load_views.sql
   Purpose  : One view per staging table that lists only the CSV columns, in CSV order.
   Why      : BULK INSERT maps CSV fields to columns by position, so it loads through these views.
               The four tracking columns stay hidden and are filled by the load procedure.
   ===================================================================== */

CREATE OR ALTER VIEW stg.v_customers_load AS 
SELECT
	customer_id,
	first_name,
	last_name,
	email,
	phone,
	gender,
	birth_date,
	signup_date,
	country,
	loyalty_tier,
	is_active
FROM stg.customers;
GO

CREATE OR ALTER VIEW stg.v_addresses_load AS 
SELECT
	address_id,
	customer_id,
	address_line,
	city,
	state,
	postal_code,
	country,
	address_type,
	is_default
FROM stg.addresses;
GO

CREATE OR ALTER VIEW stg.v_order_items_load AS 
SELECT
	order_item_id,
	order_id,
	product_id,
	quantity,
	unit_price,
	discount_pct,
	line_total
FROM stg.order_items;
GO

CREATE OR ALTER VIEW stg.v_orders_load AS 
SELECT
	order_id,
	customer_id,
	shipping_address_id,
	order_date,
	order_status,
	channel,
	currency,
	discount_code,
	total_amount
FROM stg.orders;
GO

CREATE OR ALTER VIEW stg.v_payments_load AS 
SELECT
	payment_id,
	order_id,
	payment_date,
	payment_method,
	amount,
	currency,
	payment_status,
	transaction_ref
FROM stg.payments;
GO

CREATE OR ALTER VIEW stg.v_products_load AS 
SELECT
	product_id,
	sku,
	product_name,
	category,
	brand,
	unit_price,
	cost_price,
	stock_qty,
	created_date,
	status
FROM stg.products;
GO

CREATE OR ALTER VIEW stg.v_returns_load AS 
SELECT
	return_id,
	order_item_id,
	return_date,
	reason,
	refund_amount,
	return_status,
	item_condition
FROM stg.returns;
GO

CREATE OR ALTER VIEW stg.v_reviews_load AS 
SELECT
	review_id,
	customer_id,
	product_id,
	order_id,
	rating,
	review_text,
	review_date,
	helpful_votes,
	verified_purchase
FROM stg.reviews;
GO

CREATE OR ALTER VIEW stg.v_shipments_load AS 
SELECT
	shipment_id,
	order_id,
	carrier,
	tracking_number,
	ship_date,
	delivery_date,
	shipment_status,
	shipping_cost,
	weight_kg
FROM stg.shipments;
GO

CREATE OR ALTER VIEW stg.v_support_tickets_load AS 
SELECT
	ticket_id,
	customer_id,
	order_id,
	created_at,
	resolved_at,
	category,
	priority,
	status,
	channel,
	satisfaction_score
FROM stg.support_tickets;
GO
