/* =====================================================================
   File     : 02_explore_reviews.sql
   Purpose  : Exploration queries used to design the review cleaning rules (rating, review text).
   Note     : early drafts. The final rules are in 03_clean/09_clean_reviews.sql.
   ===================================================================== */

SELECT DISTINCT rating,
CASE
	WHEN TRY_CAST(TRY_CAST(TRIM(rating) AS FLOAT) AS INT) > 5 OR TRY_CAST(TRY_CAST(TRIM(rating) AS FLOAT) AS INT) <= 0 THEN NULL
	WHEN TRY_CAST(TRY_CAST(TRIM(rating) AS FLOAT) AS INT) IN (1, 2, 3, 4, 5) THEN TRY_CAST(TRY_CAST(TRIM(rating) AS FLOAT) AS INT)
	WHEN TRIM(rating) LIKE '[0-9]%' THEN TRY_CAST(LEFT(TRIM(rating), 1) AS INT)
	WHEN UPPER(TRIM(rating)) = 'ONE' THEN 1
	WHEN UPPER(TRIM(rating)) = 'TWO' THEN 2
	WHEN UPPER(TRIM(rating)) = 'THREE' THEN 3
	WHEN UPPER(TRIM(rating)) = 'FOUR' THEN 4
	WHEN UPPER(TRIM(rating)) = 'FIVE' THEN 5
	ELSE NULL
END AS rating
FROM stg.reviews;

SELECT review_text,
CASE
	WHEN TRIM(review_text) IN ('', '-', 'NULL', 'NONE', 'NA', 'N/A') THEN NULL
	ELSE TRIM(review_text)
END
FROM stg.reviews;
