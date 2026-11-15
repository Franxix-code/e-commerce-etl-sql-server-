/* =====================================================================
   File     : 01_clean_customers.sql
   Purpose  : Cleans stg.customers and loads cln.customers: clean, fix, flag, reject, load (rules BR-C01 to BR-C08).
   Needs    : staging loaded; 03_clean/00_create_clean_tables.sql
   ===================================================================== */

CREATE OR ALTER PROCEDURE etl.usp_load_cln_customers
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        -------------------------------------------------------------------------
        -- 1) CLEAN: every staged row goes into the temp table (nothing filtered)
        -------------------------------------------------------------------------
        DROP TABLE IF EXISTS #customers_cleaned;

        SELECT
            CASE WHEN UPPER(TRIM(customer_id)) IN ('', '-', 'NA', 'NULL', 'NONE', 'N/A') THEN NULL
                 WHEN UPPER(TRIM(customer_id)) LIKE 'CUST[0-9]%' THEN 'CUST-' + SUBSTRING(UPPER(TRIM(customer_id)), 5, 20)
                 ELSE UPPER(TRIM(customer_id)) END AS customer_id,

            CASE WHEN UPPER(TRIM(first_name)) IN ('', '-', 'NA', 'NULL', 'NONE', 'N/A') THEN NULL
                 ELSE UPPER(LEFT(TRIM(first_name), 1)) + LOWER(SUBSTRING(TRIM(first_name), 2, LEN(TRIM(first_name)))) END AS first_name,
            CASE WHEN UPPER(TRIM(last_name)) IN ('', '-', 'NA', 'NULL', 'NONE', 'N/A') THEN NULL
                 ELSE UPPER(LEFT(TRIM(last_name), 1)) + LOWER(SUBSTRING(TRIM(last_name), 2, LEN(TRIM(last_name)))) END AS last_name,

            -- BR-C02: lowercase; must look like name@domain.tld, otherwise NULL
            CASE WHEN LOWER(TRIM(email)) LIKE '%_@_%._%'
                  AND LOWER(TRIM(email)) NOT LIKE '%@%@%'
                  AND LOWER(TRIM(email)) NOT LIKE '% %'
                 THEN LOWER(TRIM(email)) END AS email,

            -- BR-C03: symbols removed here, the final +234 format is set in step 2
            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(TRIM(phone), ' ', ''), '-', ''), '+', ''), '(', ''), ')', '') AS phone,

            -- BR-C06
            CASE
                WHEN UPPER(TRIM(gender)) IN ('MALE', 'M')                            THEN 'M'
                WHEN UPPER(TRIM(gender)) IN ('FEMALE', 'F')                          THEN 'F'
                WHEN UPPER(TRIM(gender)) IN ('PREFER NOT TO SAY', 'O', 'OTHER')      THEN 'O'
                ELSE NULL
            END AS gender,

            CASE
                WHEN TRIM(birth_date) LIKE '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]%'           THEN TRY_CONVERT(DATE, LEFT(TRIM(birth_date), 10), 23)   -- 2024-03-05 (time part dropped)
                WHEN TRIM(birth_date) LIKE '[0-9][0-9][0-9][0-9]/[0-9][0-9]/[0-9][0-9]'            THEN TRY_CONVERT(DATE, REPLACE(TRIM(birth_date), '/', '-'), 23)   -- 2024/03/05
                WHEN TRIM(birth_date) LIKE '[0-9][0-9]/[0-9][0-9]/[0-9][0-9][0-9][0-9]'            THEN TRY_CONVERT(DATE, TRIM(birth_date), 103)   -- 05/03/2024 (day first)
                WHEN TRIM(birth_date) LIKE '[0-9][0-9].[0-9][0-9].[0-9][0-9][0-9][0-9]'            THEN TRY_CONVERT(DATE, TRIM(birth_date), 104)   -- 05.03.2024 (day first)
                WHEN TRIM(birth_date) LIKE '[0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9]'            THEN TRY_CONVERT(DATE, TRIM(birth_date), 110)   -- 03-05-2024 (month first)
                WHEN TRIM(birth_date) LIKE '[0-9][0-9]-[0-9][0-9]-[0-9][0-9]'                      THEN TRY_CONVERT(DATE, TRIM(birth_date), 5)     -- 05-03-24 (day first)
                WHEN TRIM(birth_date) LIKE '[0-9][0-9] [A-Za-z][A-Za-z][A-Za-z] [0-9][0-9][0-9][0-9]' THEN TRY_CONVERT(DATE, TRIM(birth_date), 106) -- 05 Mar 2024
                WHEN TRIM(birth_date) LIKE '[A-Za-z]%[0-9][0-9], [0-9][0-9][0-9][0-9]'             THEN TRY_CONVERT(DATE, TRIM(birth_date), 107)   -- March 05, 2024
            END AS birth_date,
            CASE
                WHEN TRIM(signup_date) LIKE '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]%'           THEN TRY_CONVERT(DATE, LEFT(TRIM(signup_date), 10), 23)   -- 2024-03-05 (time part dropped)
                WHEN TRIM(signup_date) LIKE '[0-9][0-9][0-9][0-9]/[0-9][0-9]/[0-9][0-9]'            THEN TRY_CONVERT(DATE, REPLACE(TRIM(signup_date), '/', '-'), 23)   -- 2024/03/05
                WHEN TRIM(signup_date) LIKE '[0-9][0-9]/[0-9][0-9]/[0-9][0-9][0-9][0-9]'            THEN TRY_CONVERT(DATE, TRIM(signup_date), 103)   -- 05/03/2024 (day first)
                WHEN TRIM(signup_date) LIKE '[0-9][0-9].[0-9][0-9].[0-9][0-9][0-9][0-9]'            THEN TRY_CONVERT(DATE, TRIM(signup_date), 104)   -- 05.03.2024 (day first)
                WHEN TRIM(signup_date) LIKE '[0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9][0-9]'            THEN TRY_CONVERT(DATE, TRIM(signup_date), 110)   -- 03-05-2024 (month first)
                WHEN TRIM(signup_date) LIKE '[0-9][0-9]-[0-9][0-9]-[0-9][0-9]'                      THEN TRY_CONVERT(DATE, TRIM(signup_date), 5)     -- 05-03-24 (day first)
                WHEN TRIM(signup_date) LIKE '[0-9][0-9] [A-Za-z][A-Za-z][A-Za-z] [0-9][0-9][0-9][0-9]' THEN TRY_CONVERT(DATE, TRIM(signup_date), 106) -- 05 Mar 2024
                WHEN TRIM(signup_date) LIKE '[A-Za-z]%[0-9][0-9], [0-9][0-9][0-9][0-9]'             THEN TRY_CONVERT(DATE, TRIM(signup_date), 107)   -- March 05, 2024
            END AS signup_date,

            -- BR-C07
            CASE
                WHEN UPPER(TRIM(country)) IN ('NAIJA', 'NIGERIA', 'NG', 'NIGERA')                                  THEN 'Nigeria (NG)'
                WHEN UPPER(TRIM(country)) IN ('RSA', 'SOUTH AFRICA', 'S. AFRICA', 'ZA')                            THEN 'South Africa (ZA)'
                WHEN UPPER(TRIM(country)) IN ('US', 'USA', 'UNITED STATES', 'UNITED STATES OF AMERICA', 'U.S.A.') THEN 'United States (US)'
                WHEN UPPER(TRIM(country)) IN ('UK', 'U.K.', 'UNITED KINGDOM', 'GREAT BRITAIN', 'GB')              THEN 'United Kingdom (GB)'
                WHEN UPPER(TRIM(country)) IN ('GH', 'GHANA')                                                       THEN 'Ghana (GH)'
                WHEN UPPER(TRIM(country)) IN ('CA', 'CANADA')                                                      THEN 'Canada (CA)'
                WHEN UPPER(TRIM(country)) IN ('KE', 'KENYA', 'KENIA')                                              THEN 'Kenya (KE)'
                ELSE NULL
            END AS country,

            -- BR-C08
            CASE
                WHEN UPPER(TRIM(loyalty_tier)) = 'BRONZE'              THEN 'Bronze'
                WHEN UPPER(TRIM(loyalty_tier)) = 'SILVER'              THEN 'Silver'
                WHEN UPPER(TRIM(loyalty_tier)) = 'GOLD'                THEN 'Gold'
                WHEN UPPER(TRIM(loyalty_tier)) IN ('PLATINUM', 'PLAT') THEN 'Platinum'
                ELSE NULL
            END AS loyalty_tier,

            CASE
                WHEN UPPER(TRIM(is_active)) IN ('Y', 'YES', 'TRUE', 'ACTIVE', '1')    THEN 1
                WHEN UPPER(TRIM(is_active)) IN ('N', 'NO', 'FALSE', 'INACTIVE', '0')  THEN 0
                ELSE NULL
            END AS is_active,

            load_id,
            source_row_number,
            ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(customer_id))
                               ORDER BY source_row_number) AS rn
        INTO #customers_cleaned
        FROM stg.customers;

        -------------------------------------------------------------------------
        -- 2) FIXES that need the cleaned values
        -------------------------------------------------------------------------
        -- BR-C03: Nigerian numbers in +234XXXXXXXXXX format, anything else NULL
        UPDATE #customers_cleaned
        SET phone = CASE
                WHEN phone LIKE '%[^0-9]%'                         THEN NULL
                WHEN LEN(phone) = 11 AND phone LIKE '0%'           THEN '+234' + RIGHT(phone, 10)
                WHEN LEN(phone) = 13 AND phone LIKE '234%'         THEN '+' + phone
                WHEN LEN(phone) = 10 AND phone LIKE '[1-9]%'       THEN '+234' + phone
                ELSE NULL
            END;

        -- BR-C04: age must be between 16 and 100, otherwise NULL
        UPDATE #customers_cleaned
        SET birth_date = NULL
        WHERE birth_date IS NOT NULL
          AND birth_date NOT BETWEEN DATEADD(YEAR, -100, CAST(GETDATE() AS DATE))
                                 AND DATEADD(YEAR,  -16, CAST(GETDATE() AS DATE));

        -------------------------------------------------------------------------
        -- 3) FLAGS: the source had a real value, but the clean value is NULL
        --    (disguised nulls such as N/A do not count, nothing was lost)
        -------------------------------------------------------------------------
        ALTER TABLE #customers_cleaned ADD
            dq_invalid_email      BIT NOT NULL DEFAULT 0,
            dq_invalid_phone      BIT NOT NULL DEFAULT 0,
            dq_invalid_birth_date BIT NOT NULL DEFAULT 0;

        UPDATE c
        SET dq_invalid_email = CASE WHEN c.email IS NULL
                AND ISNULL(UPPER(TRIM(s.email)), '') NOT IN ('', '-', 'NA', 'NULL', 'NONE', 'N/A') THEN 1 ELSE 0 END,
            dq_invalid_phone = CASE WHEN c.phone IS NULL
                AND ISNULL(UPPER(TRIM(s.phone)), '') NOT IN ('', '-', 'NA', 'NULL', 'NONE', 'N/A') THEN 1 ELSE 0 END,
            dq_invalid_birth_date = CASE WHEN c.birth_date IS NULL
                AND ISNULL(UPPER(TRIM(s.birth_date)), '') NOT IN ('', '-', 'NA', 'NULL', 'NONE', 'N/A') THEN 1 ELSE 0 END
        FROM #customers_cleaned AS c
        JOIN stg.customers AS s ON s.source_row_number = c.source_row_number;

        -------------------------------------------------------------------------
        -- 4) REJECTS: one reason per row, in priority order
        -------------------------------------------------------------------------
        ALTER TABLE #customers_cleaned ADD reject_rule NVARCHAR(20) NULL, reject_reason NVARCHAR(200) NULL;

        -- BR-C01: duplicate customer_id (first row in the file is kept)
        UPDATE #customers_cleaned
        SET reject_rule = 'BR-C01', reject_reason = 'Duplicate customer_id; first row in file was kept'
        WHERE rn > 1;

        -- BR-C05: signup date in the future
        UPDATE #customers_cleaned
        SET reject_rule = 'BR-C05', reject_reason = 'signup_date is in the future'
        WHERE reject_rule IS NULL AND signup_date > CAST(GETDATE() AS DATE);

        DELETE FROM err.rejected_rows WHERE table_name = 'customers';

        INSERT INTO err.rejected_rows (load_id, table_name, source_row_number, record_key, rule_id, reason)
        SELECT load_id, 'customers', source_row_number, customer_id, reject_rule, reject_reason
        FROM #customers_cleaned
        WHERE reject_rule IS NOT NULL;

        -------------------------------------------------------------------------
        -- 5) LOAD
        -------------------------------------------------------------------------
        DELETE FROM cln.customers;

        INSERT INTO cln.customers
            (customer_id, first_name, last_name, email, phone, gender, birth_date, signup_date,
             country, loyalty_tier, is_active, dq_invalid_email, dq_invalid_phone,
             dq_invalid_birth_date, load_id, source_row_number)
        SELECT
             customer_id, first_name, last_name, email, phone, gender, birth_date, signup_date,
             country, loyalty_tier, is_active, dq_invalid_email, dq_invalid_phone,
             dq_invalid_birth_date, load_id, source_row_number
        FROM #customers_cleaned
        WHERE reject_rule IS NULL;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END;
GO
