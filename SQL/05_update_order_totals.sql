/* =====================================================================
   File     : 05_update_order_totals.sql
   Purpose  : BR-O05 and BR-O07: calculates each order total from its items and flags mismatches and orders without items.
   Needs    : cln.order_items loaded. Run again every time cln.orders is reloaded (the load empties these columns).
   ===================================================================== */

CREATE OR ALTER PROCEDURE etl.usp_update_cln_order_totals
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        -- the sum of the item line totals is the trusted total (BR-O05);
        -- a stored total that is missing, or differs by more than NGN 1.00, is flagged
        UPDATE o
        SET o.total_amount_calc = t.items_total,
            o.dq_total_mismatch = CASE WHEN o.total_amount IS NULL
                                         OR ABS(o.total_amount - t.items_total) > 1.00 THEN 1 ELSE 0 END
        FROM cln.orders AS o
        JOIN (SELECT order_id, SUM(line_total) AS items_total
              FROM cln.order_items
              GROUP BY order_id) AS t ON t.order_id = o.order_id;

        -- BR-O07: orders without any valid item
        UPDATE o
        SET o.dq_no_items = CASE WHEN EXISTS (SELECT 1 FROM cln.order_items AS i WHERE i.order_id = o.order_id)
                                 THEN 0 ELSE 1 END
        FROM cln.orders AS o;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END;
GO
