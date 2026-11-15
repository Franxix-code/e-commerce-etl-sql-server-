# Data

The pipeline reads 10 CSV files (about 1.7 million rows, 45 MB zipped). They are not stored in
the repository because of their size. Download `messy_ecommerce.zip` from the **Releases** page
and unzip the files into a folder on the machine that runs SQL Server.

| File | Rows | Primary key |
|---|---|---|
| customers | 123,600 | customer_id |
| addresses | 151,500 | address_id |
| products | 102,000 | product_id |
| orders | 202,000 | order_id |
| order_items | 388,294 | order_item_id |
| payments | 205,579 | payment_id |
| shipments | 163,609 | shipment_id |
| reviews | 151,500 | review_id |
| returns | 111,100 | return_id |
| support_tickets | 111,100 | ticket_id |

The files are synthetic and deliberately messy: duplicates, dates in 9 formats, disguised nulls,
inconsistent spellings, money with symbols, text in numeric fields, orphan keys, wrong totals.
