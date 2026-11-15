/* =====================================================================
   File     : 04_data_quality_report.sql
   Purpose  : Documentation queries: rejects by rule, data quality flag summary (view rpt.v_data_quality_flags), data dictionary, foreign keys.
   Needs    : the pipeline has run
   ===================================================================== */

-------------------------------------------------------------------------
-- 1) REJECTS BY TABLE AND RULE (the "what was removed, and why" table)
-------------------------------------------------------------------------
SELECT table_name,
       rule_id,
       MIN(reason) AS reason,
       COUNT(*) AS rows_rejected
FROM err.rejected_rows
GROUP BY table_name, rule_id
ORDER BY table_name, rows_rejected DESC;
GO

-------------------------------------------------------------------------
-- 2) DATA QUALITY FLAGS (the "what was fixed or marked" table), saved as a view
-------------------------------------------------------------------------
CREATE OR ALTER VIEW rpt.v_data_quality_flags AS
SELECT table_name,
       flag,
       meaning,
       rows_flagged,
       rows_in_table,
       CAST(100.0 * rows_flagged / NULLIF(rows_in_table, 0) AS DECIMAL(5,2)) AS pct_flagged
FROM (
    SELECT 'customers' AS table_name, 'dq_invalid_email' AS flag, 'Email present but invalid, set to NULL' AS meaning,
           SUM(CAST(dq_invalid_email AS INT)) AS rows_flagged, COUNT(*) AS rows_in_table FROM cln.customers
    UNION ALL
    SELECT 'customers' AS table_name, 'dq_invalid_phone' AS flag, 'Phone present but invalid, set to NULL' AS meaning,
           SUM(CAST(dq_invalid_phone AS INT)) AS rows_flagged, COUNT(*) AS rows_in_table FROM cln.customers
    UNION ALL
    SELECT 'customers' AS table_name, 'dq_invalid_birth_date' AS flag, 'Birth date invalid or outside age 16 to 100, set to NULL' AS meaning,
           SUM(CAST(dq_invalid_birth_date AS INT)) AS rows_flagged, COUNT(*) AS rows_in_table FROM cln.customers
    UNION ALL
    SELECT 'addresses' AS table_name, 'dq_invalid_postal_code' AS flag, 'Postal code present but invalid for the country, set to NULL' AS meaning,
           SUM(CAST(dq_invalid_postal_code AS INT)) AS rows_flagged, COUNT(*) AS rows_in_table FROM cln.addresses
    UNION ALL
    SELECT 'products' AS table_name, 'dq_sku_issue = MISSING' AS flag, 'SKU missing' AS meaning,
           SUM(CASE WHEN dq_sku_issue = 'MISSING' THEN 1 ELSE 0 END) AS rows_flagged, COUNT(*) AS rows_in_table FROM cln.products
    UNION ALL
    SELECT 'products' AS table_name, 'dq_sku_issue = DUPLICATE' AS flag, 'SKU shared by more than one product' AS meaning,
           SUM(CASE WHEN dq_sku_issue = 'DUPLICATE' THEN 1 ELSE 0 END) AS rows_flagged, COUNT(*) AS rows_in_table FROM cln.products
    UNION ALL
    SELECT 'products' AS table_name, 'dq_invalid_cost_price' AS flag, 'Cost price invalid or above the unit price, set to NULL' AS meaning,
           SUM(CAST(dq_invalid_cost_price AS INT)) AS rows_flagged, COUNT(*) AS rows_in_table FROM cln.products
    UNION ALL
    SELECT 'products' AS table_name, 'dq_stock_adjusted' AS flag, 'Negative or "out of stock" quantity set to 0' AS meaning,
           SUM(CAST(dq_stock_adjusted AS INT)) AS rows_flagged, COUNT(*) AS rows_in_table FROM cln.products
    UNION ALL
    SELECT 'orders' AS table_name, 'dq_address_issue' AS flag, 'Shipping address missing from, or not owned by, the customer; set to NULL' AS meaning,
           SUM(CAST(dq_address_issue AS INT)) AS rows_flagged, COUNT(*) AS rows_in_table FROM cln.orders
    UNION ALL
    SELECT 'orders' AS table_name, 'dq_order_before_signup' AS flag, 'Order dated before the customer signed up' AS meaning,
           SUM(CAST(dq_order_before_signup AS INT)) AS rows_flagged, COUNT(*) AS rows_in_table FROM cln.orders
    UNION ALL
    SELECT 'orders' AS table_name, 'dq_total_mismatch' AS flag, 'Stored total differs from the item total by more than NGN 1' AS meaning,
           SUM(CAST(dq_total_mismatch AS INT)) AS rows_flagged, COUNT(*) AS rows_in_table FROM cln.orders
    UNION ALL
    SELECT 'orders' AS table_name, 'dq_no_items' AS flag, 'Order has no valid items' AS meaning,
           SUM(CAST(dq_no_items AS INT)) AS rows_flagged, COUNT(*) AS rows_in_table FROM cln.orders
    UNION ALL
    SELECT 'order_items' AS table_name, 'dq_price_fallback' AS flag, 'Missing price taken from the product price' AS meaning,
           SUM(CAST(dq_price_fallback AS INT)) AS rows_flagged, COUNT(*) AS rows_in_table FROM cln.order_items
    UNION ALL
    SELECT 'payments' AS table_name, 'dq_ref_issue = MISSING' AS flag, 'Transaction reference missing (not Pay on Delivery)' AS meaning,
           SUM(CASE WHEN dq_ref_issue = 'MISSING' THEN 1 ELSE 0 END) AS rows_flagged, COUNT(*) AS rows_in_table FROM cln.payments
    UNION ALL
    SELECT 'payments' AS table_name, 'dq_ref_issue = DUPLICATE' AS flag, 'Transaction reference shared by more than one payment' AS meaning,
           SUM(CASE WHEN dq_ref_issue = 'DUPLICATE' THEN 1 ELSE 0 END) AS rows_flagged, COUNT(*) AS rows_in_table FROM cln.payments
    UNION ALL
    SELECT 'payments' AS table_name, 'dq_multiple_success' AS flag, 'More than one successful payment for the order' AS meaning,
           SUM(CAST(dq_multiple_success AS INT)) AS rows_flagged, COUNT(*) AS rows_in_table FROM cln.payments
    UNION ALL
    SELECT 'payments' AS table_name, 'dq_partial_payment' AS flag, 'Successful payment differs from the order total' AS meaning,
           SUM(CAST(dq_partial_payment AS INT)) AS rows_flagged, COUNT(*) AS rows_in_table FROM cln.payments
    UNION ALL
    SELECT 'payments' AS table_name, 'dq_date_before_order' AS flag, 'Payment dated before the order' AS meaning,
           SUM(CAST(dq_date_before_order AS INT)) AS rows_flagged, COUNT(*) AS rows_in_table FROM cln.payments
    UNION ALL
    SELECT 'shipments' AS table_name, 'dq_tracking_issue = DUPLICATE' AS flag, 'Tracking number shared by more than one shipment' AS meaning,
           SUM(CASE WHEN dq_tracking_issue = 'DUPLICATE' THEN 1 ELSE 0 END) AS rows_flagged, COUNT(*) AS rows_in_table FROM cln.shipments
    UNION ALL
    SELECT 'shipments' AS table_name, 'dq_delivery_before_ship' AS flag, 'Delivery date before ship date, delivery date set to NULL' AS meaning,
           SUM(CAST(dq_delivery_before_ship AS INT)) AS rows_flagged, COUNT(*) AS rows_in_table FROM cln.shipments
    UNION ALL
    SELECT 'shipments' AS table_name, 'dq_status_conflict' AS flag, 'Order status does not allow a shipment' AS meaning,
           SUM(CAST(dq_status_conflict AS INT)) AS rows_flagged, COUNT(*) AS rows_in_table FROM cln.shipments
    UNION ALL
    SELECT 'reviews' AS table_name, 'dq_invalid_rating' AS flag, 'Rating outside 1 to 5, set to NULL' AS meaning,
           SUM(CAST(dq_invalid_rating AS INT)) AS rows_flagged, COUNT(*) AS rows_in_table FROM cln.reviews
    UNION ALL
    SELECT 'reviews' AS table_name, 'dq_date_before_order' AS flag, 'Review dated before the order' AS meaning,
           SUM(CAST(dq_date_before_order AS INT)) AS rows_flagged, COUNT(*) AS rows_in_table FROM cln.reviews
    UNION ALL
    SELECT 'returns' AS table_name, 'dq_return_window' AS flag, 'Return more than 45 days after the order, or before it' AS meaning,
           SUM(CAST(dq_return_window AS INT)) AS rows_flagged, COUNT(*) AS rows_in_table FROM cln.returns
    UNION ALL
    SELECT 'returns' AS table_name, 'dq_refund_capped' AS flag, 'Refund above the item total, reduced to the item total' AS meaning,
           SUM(CAST(dq_refund_capped AS INT)) AS rows_flagged, COUNT(*) AS rows_in_table FROM cln.returns
    UNION ALL
    SELECT 'support_tickets' AS table_name, 'dq_order_issue' AS flag, 'Order missing or not owned by the customer, set to NULL' AS meaning,
           SUM(CAST(dq_order_issue AS INT)) AS rows_flagged, COUNT(*) AS rows_in_table FROM cln.support_tickets
    UNION ALL
    SELECT 'support_tickets' AS table_name, 'dq_resolution_issue' AS flag, 'Resolved before created, or open ticket with a resolved date' AS meaning,
           SUM(CAST(dq_resolution_issue AS INT)) AS rows_flagged, COUNT(*) AS rows_in_table FROM cln.support_tickets
) AS f;
GO

SELECT * FROM rpt.v_data_quality_flags ORDER BY table_name, flag;
GO

-------------------------------------------------------------------------
-- 3) DATA DICTIONARY for the clean and reporting layers
-------------------------------------------------------------------------
SELECT TABLE_SCHEMA AS layer,
       TABLE_NAME AS table_name,
       ORDINAL_POSITION AS position,
       COLUMN_NAME AS column_name,
       DATA_TYPE AS data_type,
       CHARACTER_MAXIMUM_LENGTH AS max_length,
       NUMERIC_PRECISION AS num_precision,
       NUMERIC_SCALE AS num_scale,
       IS_NULLABLE AS nullable
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA IN ('cln', 'rpt')
ORDER BY TABLE_SCHEMA, TABLE_NAME, ORDINAL_POSITION;
GO

-------------------------------------------------------------------------
-- 4) RELATIONSHIPS (one row per foreign key, for the ER diagram)
-------------------------------------------------------------------------
SELECT OBJECT_SCHEMA_NAME(fk.parent_object_id) + '.' + OBJECT_NAME(fk.parent_object_id) AS child_table,
       child_col.name AS child_column,
       OBJECT_SCHEMA_NAME(fk.referenced_object_id) + '.' + OBJECT_NAME(fk.referenced_object_id) AS parent_table,
       parent_col.name AS parent_column,
       fk.name AS constraint_name
FROM sys.foreign_keys AS fk
JOIN sys.foreign_key_columns AS fkc ON fkc.constraint_object_id = fk.object_id
JOIN sys.columns AS child_col  ON child_col.object_id  = fkc.parent_object_id
                              AND child_col.column_id  = fkc.parent_column_id
JOIN sys.columns AS parent_col ON parent_col.object_id = fkc.referenced_object_id
                              AND parent_col.column_id = fkc.referenced_column_id
WHERE OBJECT_SCHEMA_NAME(fk.parent_object_id) = 'cln'
ORDER BY child_table, child_column;
