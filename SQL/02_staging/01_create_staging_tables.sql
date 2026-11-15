/* =====================================================================
   File     : 01_create_staging_tables.sql
   Purpose  : Staging tables: the CSV columns as text, plus source_row_number (IDENTITY), load_id, source_file and loaded_at.
   Needs    : 01_setup
   Note     : CSV fields are loaded through the views in 02_create_load_views.sql, which hide the four tracking columns.
   ===================================================================== */

-- customers
IF OBJECT_ID('stg.customers', 'U') IS NOT NULL
	DROP TABLE stg.customers;
CREATE TABLE stg.customers (
	source_row_number INT IDENTITY(1, 1),
	customer_id NVARCHAR(50),
	first_name NVARCHAR(50),
	last_name NVARCHAR(50),
	email NVARCHAR(50),
	phone NVARCHAR(50),
	gender NVARCHAR(50),
	birth_date NVARCHAR(50),
	signup_date NVARCHAR(50),
	country NVARCHAR(50),
	loyalty_tier NVARCHAR(50),
	is_active NVARCHAR(50),
	load_id INT,
	source_file NVARCHAR(50),
	loaded_at DATETIME2 DEFAULT SYSDATETIME()
);
GO

IF OBJECT_ID('stg.addresses', 'U') IS NOT NULL
	DROP TABLE stg.addresses;
CREATE TABLE stg.addresses (
	source_row_number INT IDENTITY(1, 1),
	address_id NVARCHAR(50),
	customer_id NVARCHAR(50),
	address_line NVARCHAR(50),
	city NVARCHAR(50),
	state NVARCHAR(50),
	postal_code NVARCHAR(50),
	country NVARCHAR(50),
	address_type NVARCHAR(50),
	is_default NVARCHAR(50),
	load_id INT,
	source_file NVARCHAR(50),
	loaded_at DATETIME2 DEFAULT SYSDATETIME()
);
GO

IF OBJECT_ID('stg.order_items', 'U') IS NOT NULL
	DROP TABLE stg.order_items;
CREATE TABLE stg.order_items (
	source_row_number INT IDENTITY(1, 1),
	order_item_id NVARCHAR(50),
	order_id NVARCHAR(50),
	product_id NVARCHAR(50),
	quantity NVARCHAR(50),
	unit_price NVARCHAR(50),
	discount_pct NVARCHAR(50),
	line_total NVARCHAR(50),
	load_id INT,
	source_file NVARCHAR(50),
	loaded_at DATETIME2 DEFAULT SYSDATETIME()
);
GO

IF OBJECT_ID('stg.orders', 'U') IS NOT NULL
	DROP TABLE stg.orders;
CREATE TABLE stg.orders (
	source_row_number INT IDENTITY(1, 1),
	order_id NVARCHAR(50),
	customer_id NVARCHAR(50),
	shipping_address_id NVARCHAR(50),
	order_date NVARCHAR(50),
	order_status NVARCHAR(50),
	channel NVARCHAR(50),
	currency NVARCHAR(50),
	discount_code NVARCHAR(50),
	total_amount NVARCHAR(50),
	load_id INT,
	source_file NVARCHAR(50),
	loaded_at DATETIME2 DEFAULT SYSDATETIME()
);
GO

IF OBJECT_ID('stg.products', 'U') IS NOT NULL
	DROP TABLE stg.products;
CREATE TABLE stg.products (
	source_row_number INT IDENTITY(1, 1),
	product_id NVARCHAR(50),
	sku NVARCHAR(50),
	product_name NVARCHAR(50),
	category NVARCHAR(50),
	brand NVARCHAR(50),
	unit_price NVARCHAR(50),
	cost_price NVARCHAR(50),
	stock_qty NVARCHAR(50),
	created_date NVARCHAR(50),
	status NVARCHAR(50),
	load_id INT,
	source_file NVARCHAR(50),
	loaded_at DATETIME2 DEFAULT SYSDATETIME()
);
GO

IF OBJECT_ID('stg.payments', 'U') IS NOT NULL
	DROP TABLE stg.payments;
CREATE TABLE stg.payments (
	source_row_number INT IDENTITY(1, 1),
	payment_id NVARCHAR(50),
	order_id NVARCHAR(50),
	payment_date NVARCHAR(50),
	payment_method NVARCHAR(50),
	amount NVARCHAR(50),
	currency NVARCHAR(50),
	payment_status NVARCHAR(50),
	transaction_ref NVARCHAR(50),
	load_id INT,
	source_file NVARCHAR(50),
	loaded_at DATETIME2 DEFAULT SYSDATETIME()
);
GO

IF OBJECT_ID('stg.returns', 'U') IS NOT NULL
	DROP TABLE stg.returns;
CREATE TABLE stg.returns (
	source_row_number INT IDENTITY(1, 1),
	return_id NVARCHAR(50),
	order_item_id NVARCHAR(50),
	return_date NVARCHAR(50),
	reason NVARCHAR(50),
	refund_amount NVARCHAR(50),
	return_status NVARCHAR(50),
	item_condition NVARCHAR(50),
	load_id INT,
	source_file NVARCHAR(50),
	loaded_at DATETIME2 DEFAULT SYSDATETIME()
);
GO

IF OBJECT_ID('stg.reviews', 'U') IS NOT NULL
	DROP TABLE stg.reviews;
CREATE TABLE stg.reviews (
	source_row_number INT IDENTITY(1, 1),
	review_id NVARCHAR(50),
	customer_id NVARCHAR(50),
	product_id NVARCHAR(50),
	order_id NVARCHAR(50),
	rating NVARCHAR(50),
	review_text NVARCHAR(100),
	review_date NVARCHAR(50),
	helpful_votes NVARCHAR(50),
	verified_purchase NVARCHAR(50),
	load_id INT,
	source_file NVARCHAR(50),
	loaded_at DATETIME2 DEFAULT SYSDATETIME()
);
GO

IF OBJECT_ID('stg.shipments', 'U') IS NOT NULL
	DROP TABLE stg.shipments;
CREATE TABLE stg.shipments (
	source_row_number INT IDENTITY(1, 1),
	shipment_id NVARCHAR(50),
	order_id NVARCHAR(50),
	carrier NVARCHAR(50),
	tracking_number NVARCHAR(50),
	ship_date NVARCHAR(50),
	delivery_date NVARCHAR(50),
	shipment_status NVARCHAR(50),
	shipping_cost NVARCHAR(50),
	weight_kg NVARCHAR(50),
	load_id INT,
	source_file NVARCHAR(50),
	loaded_at DATETIME2 DEFAULT SYSDATETIME()
);
GO

IF OBJECT_ID('stg.support_tickets', 'U') IS NOT NULL
	DROP TABLE stg.support_tickets;
CREATE TABLE stg.support_tickets (
	source_row_number INT IDENTITY(1, 1),
	ticket_id NVARCHAR(50),
	customer_id NVARCHAR(50),
	order_id NVARCHAR(50),
	created_at NVARCHAR(50),
	resolved_at NVARCHAR(50),
	category NVARCHAR(50),
	priority NVARCHAR(50),
	status NVARCHAR(50),
	channel NVARCHAR(50),
	satisfaction_score NVARCHAR(50),
	load_id INT,
	source_file NVARCHAR(50),
	loaded_at DATETIME2 DEFAULT SYSDATETIME()
);
GO
