/* =====================================================================
   File     : 01_explore_products.sql
   Purpose  : Exploration queries used to design the product cleaning rules (categories, status, stock).
   Note     : early drafts. The final rules are in 03_clean/03_clean_products.sql (for stock, blank or unreadable
              values stay NULL there; only negative numbers and the text out of stock become 0).
   ===================================================================== */

SELECT DISTINCT UPPER(TRIM(category)),
CASE
	WHEN UPPER(TRIM(category)) LIKE '%ELECTRONIC%' THEN 'Electronics'
	WHEN UPPER(TRIM(category)) LIKE '%SPORT%' THEN 'Sport'
	WHEN UPPER(TRIM(category)) LIKE '%BEAUTY%' THEN 'Beauty'
	WHEN UPPER(TRIM(category)) LIKE '%HOME%' THEN 'Home and Kitchen'
	WHEN UPPER(TRIM(category)) LIKE '%HEALTH%' THEN 'Health'
	WHEN UPPER(TRIM(category)) LIKE '%FASHION%' THEN 'Fashion'
	WHEN UPPER(TRIM(category)) LIKE '%GROCER%' THEN 'Grocery'
	WHEN UPPER(TRIM(category)) LIKE '%BOOK%' THEN 'Books'
	WHEN UPPER(TRIM(category)) LIKE '%AUTO%' THEN 'Automotive'
	WHEN UPPER(TRIM(category)) LIKE '%TOY%' THEN 'Games'
	ELSE NULL
END 
FROM stg.products;

SELECT DISTINCT status,
CASE
	WHEN UPPER(TRIM(status)) IN ('A', 'ACTIVE', '1') THEN 'Active'
	WHEN UPPER(TRIM(status)) IN ('I', 'INACTIVE') THEN 'Inactive'
	WHEN UPPER(TRIM(status)) LIKE '%DIS%' THEN 'Discontinued'
END
FROM stg.products;


SELECT 
stock_qty,
TRY_CAST(stock_qty AS INT) AS qty,
CASE
	WHEN TRY_CAST(stock_qty AS INT) <= 0 OR TRY_CAST(stock_qty AS INT) IS NULL THEN 0
	WHEN UPPER(TRIM(stock_qty)) LIKE '%OUT%' THEN 0
	ELSE CAST(stock_qty AS INT)
END n
FROM stg.products;
