/* =====================================================================
   File     : 00_create_clean_tables.sql
   Purpose  : Clean-layer tables with primary keys, foreign keys and the dq_ flag columns.
   Needs    : 01_setup
   Note     : drops and recreates all ten tables (children first). Run once, or when the design changes.
   ===================================================================== */

-- Drop in dependency order: children first
IF OBJECT_ID('cln.returns', 'U') IS NOT NULL				DROP TABLE cln.returns;
IF OBJECT_ID('cln.support_tickets', 'U') IS NOT NULL		DROP TABLE cln.support_tickets;
IF OBJECT_ID('cln.reviews', 'U') IS NOT NULL				DROP TABLE cln.reviews;
IF OBJECT_ID('cln.shipments', 'U') IS NOT NULL				DROP TABLE cln.shipments;
IF OBJECT_ID('cln.payments', 'U') IS NOT NULL				DROP TABLE cln.payments;
IF OBJECT_ID('cln.order_items', 'U') IS NOT NULL			DROP TABLE cln.order_items;
IF OBJECT_ID('cln.orders', 'U') IS NOT NULL					DROP TABLE cln.orders;
IF OBJECT_ID('cln.addresses', 'U') IS NOT NULL				DROP TABLE cln.addresses;
IF OBJECT_ID('cln.customers', 'U') IS NOT NULL				DROP TABLE cln.customers;
IF OBJECT_ID('cln.products', 'U') IS NOT NULL				DROP TABLE cln.products;



--- creating cln.products table ----
CREATE TABLE cln.products (
	product_id VARCHAR(20) NOT NULL PRIMARY KEY,
	sku NVARCHAR(50),
	product_name NVARCHAR(100),
	category NVARCHAR(20),
	brand NVARCHAR(20),
	unit_price DECIMAL(10, 2),
	cost_price DECIMAL(10, 2),
	stock_qty INT,
	created_date DATE,
	status NVARCHAR(50),
	dq_sku_issue NVARCHAR(20) NULL,
	dq_invalid_cost_price BIT NOT NULL DEFAULT 0,
	dq_stock_adjusted BIT NOT NULL DEFAULT 0,
	load_id INT,
	source_row_number INT,
	loaded_at DATETIME2 DEFAULT SYSDATETIME()
);
GO

-- BR-P02: SKU uniqueness is enforced only for rows without a SKU issue
CREATE UNIQUE INDEX uq_products_sku ON cln.products (sku)
WHERE sku IS NOT NULL AND dq_sku_issue IS NULL;
GO


--- creating cln.customers table ----
CREATE TABLE cln.customers (
	customer_id VARCHAR(20) NOT NULL PRIMARY KEY,
	first_name NVARCHAR(100),
	last_name NVARCHAR(100),
	email NVARCHAR(200),
	phone VARCHAR(20),
	gender CHAR(1),
	birth_date DATE,
	signup_date DATE,
	country NVARCHAR(50),
	loyalty_tier NVARCHAR(50),
	is_active BIT,
	dq_invalid_email BIT NOT NULL DEFAULT 0,
	dq_invalid_phone BIT NOT NULL DEFAULT 0,
	dq_invalid_birth_date BIT NOT NULL DEFAULT 0,
	load_id INT,
	source_row_number INT,
	loaded_at DATETIME2 NOT NULL DEFAULT SYSDATETIME()
);
GO


--- creating cln.addresses table ----
CREATE TABLE cln.addresses (
	address_id VARCHAR(20) PRIMARY KEY,
	customer_id VARCHAR(20) NOT NULL FOREIGN KEY REFERENCES cln.customers (customer_id),
	address_line NVARCHAR(50),
	city NVARCHAR(50),
	state NVARCHAR(50),
	postal_code VARCHAR(10),
	country NVARCHAR(50),
	address_type NVARCHAR(50),
	is_default BIT,
	dq_invalid_postal_code BIT NOT NULL DEFAULT 0,
	load_id INT,
	source_row_number INT,
	loaded_at DATETIME2 NOT NULL DEFAULT SYSDATETIME()
);
GO


--- creating cln.orders table ----
CREATE TABLE cln.orders (
	order_id VARCHAR(20) NOT NULL PRIMARY KEY,
	customer_id VARCHAR(20) FOREIGN KEY REFERENCES cln.customers (customer_id),
	shipping_address_id VARCHAR(20) FOREIGN KEY REFERENCES cln.addresses (address_id),
	order_date DATE,
	order_status NVARCHAR(20),
	channel NVARCHAR(20),
	currency NVARCHAR(10),
	discount_code NVARCHAR(20),
	total_amount DECIMAL(10, 2),
	total_amount_calc DECIMAL(18, 2) NULL,
	dq_address_issue BIT NOT NULL DEFAULT 0,
	dq_order_before_signup BIT NOT NULL DEFAULT 0,
	dq_total_mismatch BIT NULL,
	dq_no_items BIT NULL,
	load_id INT,
	source_row_number INT,
	loaded_at DATETIME2 DEFAULT SYSDATETIME()
);
GO


--- creating cln.order_items table ----
CREATE TABLE cln.order_items (	
	order_item_id VARCHAR(20) NOT NULL PRIMARY KEY,
	order_id VARCHAR(20) NOT NULL FOREIGN KEY REFERENCES cln.orders (order_id),
	product_id VARCHAR(20) NOT NULL FOREIGN KEY REFERENCES cln.products (product_id),
	quantity INT,
	unit_price DECIMAL(18, 2),
	discount_pct DECIMAL(5, 2),
	line_total DECIMAL(18, 2),
	dq_price_fallback BIT NOT NULL DEFAULT 0,
	load_id INT,
	source_row_number INT,
	loaded_at DATETIME2 DEFAULT SYSDATETIME()
);
GO



--- creating cln.payments table ----
CREATE TABLE cln.payments (
	payment_id VARCHAR(20) NOT NULL PRIMARY KEY,
	order_id VARCHAR(20) NOT NULL FOREIGN KEY REFERENCES cln.orders (order_id),
	payment_date DATE,
	payment_method NVARCHAR(50),
	amount DECIMAL(18,2 ),
	currency NVARCHAR(50),
	payment_status NVARCHAR(50),
	transaction_ref NVARCHAR(50),
	dq_ref_issue NVARCHAR(20) NULL,
	dq_multiple_success BIT NOT NULL DEFAULT 0,
	dq_partial_payment BIT NOT NULL DEFAULT 0,
	dq_date_before_order BIT NOT NULL DEFAULT 0,
	load_id INT NULL,
	source_row_number INT NULL,
	loaded_at DATETIME2 DEFAULT SYSDATETIME()
);
GO

--- creating cln.shipments table ----
CREATE TABLE cln.shipments (
	shipment_id VARCHAR(20) NOT NULL PRIMARY KEY,
	order_id VARCHAR(20) NOT NULL FOREIGN KEY REFERENCES cln.orders (order_id),
	carrier NVARCHAR(50),
	tracking_number NVARCHAR(50),
	ship_date DATE,
	delivery_date DATE,
	shipment_status NVARCHAR(50),
	shipping_cost DECIMAL(18,2),
	weight_kg DECIMAL(8,2),
	dq_tracking_issue NVARCHAR(20) NULL,
	dq_delivery_before_ship BIT NOT NULL DEFAULT 0,
	dq_status_conflict BIT NOT NULL DEFAULT 0,
	load_id INT,
	source_row_number INT,
	loaded_at DATETIME2 DEFAULT SYSDATETIME()
);
GO


--- creating cln.reviews table ----
CREATE TABLE cln.reviews (
	review_id VARCHAR(20) NOT NULL PRIMARY KEY,
	customer_id VARCHAR(20) NOT NULL FOREIGN KEY REFERENCES cln.customers (customer_id),
	product_id VARCHAR(20) NOT NULL FOREIGN KEY REFERENCES cln.products (product_id),
	order_id VARCHAR(20) NOT NULL FOREIGN KEY REFERENCES cln.orders (order_id),
	rating TINYINT,
	review_text NVARCHAR(1000) NULL,
	review_date DATE,
	helpful_votes INT,
	verified_purchase BIT NULL,
	dq_invalid_rating BIT NOT NULL DEFAULT 0,
	dq_date_before_order BIT NOT NULL DEFAULT 0,
	load_id INT,
	source_row_number INT,
	loaded_at DATETIME2 DEFAULT SYSDATETIME()
);
GO


--- creating cln.returns table ----
CREATE TABLE cln.returns (
	return_id VARCHAR(20) NOT NULL PRIMARY KEY,
	order_item_id VARCHAR(20) NOT NULL FOREIGN KEY REFERENCES cln.order_items (order_item_id),
	return_date DATE,
	reason NVARCHAR(30),
	refund_amount DECIMAL(18,2),
	return_status NVARCHAR(20),
	item_condition NVARCHAR(20),
	dq_return_window BIT NOT NULL DEFAULT 0,
	dq_refund_capped BIT NOT NULL DEFAULT 0,
	load_id INT,
	source_row_number INT,
	loaded_at DATETIME2 DEFAULT SYSDATETIME()
);
GO



--- creating cln.support_tickets table ----
CREATE TABLE cln.support_tickets (
	ticket_id VARCHAR(20) NOT NULL PRIMARY KEY,
	customer_id VARCHAR(20) NOT NULL FOREIGN KEY REFERENCES cln.customers (customer_id),
	order_id VARCHAR(20) FOREIGN KEY REFERENCES cln.orders (order_id),
	created_at DATE NULL,
	resolved_at DATE NULL,
	category NVARCHAR(20) NULL,
	priority NVARCHAR(20) NULL,
	status NVARCHAR(20) NULL,
	channel NVARCHAR(20),
	satisfaction_score TINYINT NULL,
	dq_order_issue BIT NOT NULL DEFAULT 0,
	dq_resolution_issue BIT NOT NULL DEFAULT 0,
	load_id INT,
	source_row_number INT,
	loaded_at DATETIME2 DEFAULT SYSDATETIME()
);
GO
