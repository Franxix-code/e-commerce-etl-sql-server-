/* =====================================================================
   File     : 01_create_report_tables.sql
   Purpose  : The 13 reporting tables for the nine KPI groups of the specification (section 9).
   Needs    : the clean layer (the tables are filled by etl.usp_build_rpt)
   ===================================================================== */

--- KPI 1: Monthly revenue by country and channel
IF OBJECT_ID('rpt.monthly_revenue', 'U') IS NOT NULL
	DROP TABLE rpt.monthly_revenue;
CREATE TABLE rpt.monthly_revenue (
	order_month		DATE NOT NULL,
	country NVARCHAR(50) NOT NULL,
	channel NVARCHAR(50) NOT NULL,
	order_count INT NOT NULL,
	gross_revenue DECIMAL(18, 2) NOT NULL,
	avg_order_value DECIMAL(18, 2) NOT NULL,
	CONSTRAINT pk_monthly_revenue PRIMARY KEY (order_month, country, channel)
);
GO

-- KPI 2: Average order value and items per order, by month revenue
IF OBJECT_ID('rpt.order_value_monthly', 'U') IS NOT NULL
	DROP TABLE rpt.order_value_monthly;
CREATE TABLE rpt.order_value_monthly (
	order_month DATE NOT NULL PRIMARY KEY,
	order_count INT NOT NULL,
	avg_order_value DECIMAL(18, 2) NOT NULL,
	avg_items_per_order DECIMAL(10, 2) NOT NULL,
	avg_units_per_order DECIMAL(10, 2) NOT NULL
); 
GO

-- KPI 3: top products and categories by revenue
IF OBJECT_ID('rpt.product_revenue', 'U') IS NOT NULL
	DROP TABLE rpt.product_revenue;
CREATE TABLE rpt.product_revenue (
	product_id VARCHAR(20) NOT NULL PRIMARY KEY,
	product_name NVARCHAR(500) NULL,
	category NVARCHAR(50) NOT NULL,
	brand NVARCHAR(50) NULL,
	units_sold INT NOT NULL,
	revenue DECIMAL(18, 2) NOT NULL,
	revenue_rank INT NOT NULL,
	category_rank INT NOT NULL
); 
GO

IF OBJECT_ID('rpt.category_revenue', 'U') IS NOT NULL
	DROP TABLE rpt.category_revenue;
CREATE TABLE rpt.category_revenue (
	category NVARCHAR(50) NOT NULL PRIMARY KEY,
	product_sold INT NOT NULL,
	units_sold INT NOT NULL,
	revenue DECIMAL(18, 2) NOT NULL,
	revenue_share_pct DECIMAL(5, 2) NOT NULL 
); 
GO

-- KPI 4: payment success rate by method
IF OBJECT_ID('rpt.payment_success_by_method', 'U') IS NOT NULL
	DROP TABLE rpt.payment_success_by_method;
CREATE TABLE rpt.payment_success_by_method (
	payment_method NVARCHAR(50) NOT NULL PRIMARY KEY,
	total_payments INT NOT NULL,
	successful INT NOT NULL,
	failed INT NOT NULL,
	pending INT NOT NULL,
	refunded INT NOT NULL,
	success_rate_pct DECIMAL(5, 2) NOT NULL,
	successful_amount DECIMAL(18, 2) NOT NULL
); 
GO

-- KPI 5: delivery time by carrier
IF OBJECT_ID('rpt.delivery_by_carrier', 'U') IS NOT NULL
	DROP TABLE rpt.delivery_by_carrier;
CREATE TABLE rpt.delivery_by_carrier (
	carrier NVARCHAR(30) NOT NULL PRIMARY KEY,
	shipments INT NOT NULL,
	delivered_shipments INT NOT NULL,
	avg_days_to_ship DECIMAL(10, 2) NULL,
	avg_days_to_transit DECIMAL(10, 2) NULL,
	avg_days_order_to_delivery DECIMAL(10, 2) NULL
); 
GO

-- KPI 6: return rate by category, and top return reasons
IF OBJECT_ID('rpt.return_rate_by_category', 'U') IS NOT NULL
	DROP TABLE rpt.return_rate_by_category;
CREATE TABLE rpt.return_rate_by_category (
	category NVARCHAR(50) NOT NULL PRIMARY KEY,
	items_sold INT NOT NULL,
	items_returned INT NOT NULL,
	return_rate_pct DECIMAL(5, 2) NOT NULL,
	refunded_amount DECIMAL(18, 2) NOT NULL
); 
GO

IF OBJECT_ID('rpt.return_reasons', 'U') IS NOT NULL
	DROP TABLE rpt.return_reasons;
CREATE TABLE rpt.return_reasons (
	reason NVARCHAR(50) NOT NULL PRIMARY KEY,
	return_count INT NOT NULL,
	share_pct DECIMAL(5, 2) NOT NULL,
	refunded_amount DECIMAL(18, 2) NOT NULL,
	reason_rank INT NOT NULL
); 
GO

-- KPI 7: average review rating by product and by category
IF OBJECT_ID('rpt.product_ratings', 'U') IS NOT NULL
	DROP TABLE rpt.product_ratings;
CREATE TABLE rpt.product_ratings (
	product_id VARCHAR(20) NOT NULL PRIMARY KEY,
	product_name NVARCHAR(500) NOT NULL,
	category NVARCHAR(50) NOT NULL,
	review_count INT NOT NULL,
	avg_rating DECIMAL(3, 2) NOT NULL
); 
GO

IF OBJECT_ID('rpt.category_ratings', 'U') IS NOT NULL
	DROP TABLE rpt.category_ratings;
CREATE TABLE rpt.category_ratings (
	category NVARCHAR(50) NOT NULL PRIMARY KEY,
	review_count INT NOT NULL,
	avg_rating DECIMAL(3, 2) NOT NULL
); 
GO

-- KPI 8: ticket volume and resolution time by category 
IF OBJECT_ID('rpt.ticket_statistics', 'U') IS NOT NULL
	DROP TABLE rpt.ticket_statistics;
CREATE TABLE rpt.ticket_statistics (
	category NVARCHAR(50) NOT NULL PRIMARY KEY,
	ticket_count INT NOT NULL,
	open_tickets INT NOT NULL,
	resolved_tickets INT NOT NULL,
	avg_resolution_days DECIMAL(10, 2) NULL,
	avg_satisfaction DECIMAL(3, 2) NULL
); 
GO

-- KPI 9: customer segmentation and lifetime value
IF OBJECT_ID('rpt.customer_ltv', 'U') IS NOT NULL
	DROP TABLE rpt.customer_ltv;
CREATE TABLE rpt.customer_ltv (
	customer_id VARCHAR(20) NOT NULL PRIMARY KEY,
	country NVARCHAR(50) NOT NULL,
	loyalty_tier NVARCHAR(50) NULL,
	delivered_orders INT NOT  NULL,
	first_order_date DATE NULL,
	last_order_date DATE NULL,
	lifetime_value DECIMAL(18, 2) NOT NULL,
	refunds DECIMAL(18, 2) NOT NULL,
	net_lifetime_value DECIMAL(18, 2) NOT NULL,
	avg_order_value DECIMAL(18, 2) NULL,
	segment NVARCHAR(20) NOT NULL
); 
GO

IF OBJECT_ID('rpt.customer_segment_summary', 'U') IS NOT NULL
	DROP TABLE rpt.customer_segment_summary;
CREATE TABLE rpt.customer_segment_summary (
	segment NVARCHAR(20) NOT NULL PRIMARY KEY,
	customer_count INT NOT NULL,
	total_lifetime_value DECIMAL(18, 2) NOT NULL,
	avg_lifetime_value DECIMAL(18, 2) NOT NULL,
	pct_of_customers DECIMAL(5, 2) NOT NULL,
	pct_of_revenue DECIMAL(5, 2) NOT NULL
); 
GO
