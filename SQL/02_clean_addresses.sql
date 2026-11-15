/* =====================================================================
   File     : 02_clean_addresses.sql
   Purpose  : Cleans stg.addresses and loads cln.addresses (rules BR-A01 to BR-A06).
   Needs    : cln.customers loaded (foreign key)
   ===================================================================== */

CREATE OR ALTER PROCEDURE etl.usp_load_cln_addresses
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRAN;

        -------------------------------------------------------------------------
        -- 1) CLEAN: every staged row goes into the temp table (nothing filtered)
        -------------------------------------------------------------------------
        DROP TABLE IF EXISTS #addresses_cleaned;

        SELECT
            CASE WHEN UPPER(TRIM(address_id)) IN ('', '-', 'NA', 'NULL', 'NONE', 'N/A') THEN NULL
                 WHEN UPPER(TRIM(address_id)) LIKE 'ADDR[0-9]%' THEN 'ADDR-' + SUBSTRING(UPPER(TRIM(address_id)), 5, 20)
                 ELSE UPPER(TRIM(address_id)) END AS address_id,
            CASE WHEN UPPER(TRIM(customer_id)) IN ('', '-', 'NA', 'NULL', 'NONE', 'N/A') THEN NULL
                 WHEN UPPER(TRIM(customer_id)) LIKE 'CUST[0-9]%' THEN 'CUST-' + SUBSTRING(UPPER(TRIM(customer_id)), 5, 20)
                 ELSE UPPER(TRIM(customer_id)) END AS customer_id,

            -- trimmed here; St./Rd expanded; capitalised word by word in step 2
            CASE WHEN UPPER(TRIM(address_line)) IN ('', '-', 'NA', 'NULL', 'NONE', 'N/A') THEN NULL
                 ELSE REPLACE(REPLACE(TRIM(address_line), ' St.', ' Street'), ' Rd', ' Road') END AS address_line,

            CASE
                WHEN UPPER(TRIM(city)) IN ('', '-', 'NA', 'NULL', 'NONE', 'N/A')            THEN NULL
                WHEN UPPER(TRIM(city)) = 'PORT HARCOURT'  THEN 'Port Harcourt'
                WHEN UPPER(TRIM(city)) = 'BENIN CITY'     THEN 'Benin City'
                WHEN UPPER(TRIM(city)) = 'CAPE TOWN'      THEN 'Cape Town'
                WHEN UPPER(TRIM(city)) = 'NEW YORK'       THEN 'New York'
                ELSE UPPER(LEFT(TRIM(city), 1)) + LOWER(SUBSTRING(TRIM(city), 2, LEN(TRIM(city))))
            END AS city,

            CASE
                WHEN UPPER(TRIM(state)) IN ('', '-', 'NA', 'NULL', 'NONE', 'N/A')   THEN NULL
                WHEN UPPER(TRIM(state)) IN ('FCT', 'NY', 'TX', 'GA', 'IL', 'ON', 'BC', 'AB') THEN UPPER(TRIM(state))
                WHEN UPPER(TRIM(state)) = 'GREATER ACCRA'  THEN 'Greater Accra'
                WHEN UPPER(TRIM(state)) = 'WESTERN CAPE'   THEN 'Western Cape'
                WHEN UPPER(TRIM(state)) = 'KWAZULU-NATAL'  THEN 'KwaZulu-Natal'
                ELSE UPPER(LEFT(TRIM(state), 1)) + LOWER(SUBSTRING(TRIM(state), 2, LEN(TRIM(state))))
            END AS state,

            NULLIF(TRIM(postal_code), '') AS postal_code,

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

            -- BR-A05
            CASE
                WHEN UPPER(TRIM(address_type)) IN ('HOME', 'HOUSE')        THEN 'Home'
                WHEN UPPER(TRIM(address_type)) IN ('WORK', 'OFFICE')       THEN 'Work'
                WHEN UPPER(TRIM(address_type)) = 'BILLING'                 THEN 'Billing'
                WHEN UPPER(TRIM(address_type)) IN ('SHIPPING', 'SHIP TO')  THEN 'Shipping'
                ELSE NULL
            END AS address_type,

            CASE
                WHEN UPPER(TRIM(is_default)) IN ('Y', 'YES', 'TRUE', '1')  THEN 1
                WHEN UPPER(TRIM(is_default)) IN ('N', 'NO', 'FALSE', '0')  THEN 0
                ELSE NULL
            END AS is_default,

            load_id,
            source_row_number,
            ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(address_id))
                               ORDER BY source_row_number) AS rn
        INTO #addresses_cleaned
        FROM stg.addresses;

        -------------------------------------------------------------------------
        -- 2) FIXES that need the cleaned values
        -------------------------------------------------------------------------
        -- address line: capitalise every word (works for addresses of up to 4 words)
        ALTER TABLE #addresses_cleaned ADD address_dotted NVARCHAR(128);

        UPDATE #addresses_cleaned
        SET address_dotted = REPLACE(address_line, ' ', '.');

        UPDATE #addresses_cleaned
        SET address_line = NULLIF(CONCAT_WS(' ',
                UPPER(LEFT(PARSENAME(address_dotted, 4), 1)) + LOWER(SUBSTRING(PARSENAME(address_dotted, 4), 2, 50)),
                UPPER(LEFT(PARSENAME(address_dotted, 3), 1)) + LOWER(SUBSTRING(PARSENAME(address_dotted, 3), 2, 50)),
                UPPER(LEFT(PARSENAME(address_dotted, 2), 1)) + LOWER(SUBSTRING(PARSENAME(address_dotted, 2), 2, 50)),
                UPPER(LEFT(PARSENAME(address_dotted, 1), 1)) + LOWER(SUBSTRING(PARSENAME(address_dotted, 1), 2, 50))
            ), '')
        WHERE address_line IS NOT NULL;

        ALTER TABLE #addresses_cleaned DROP COLUMN address_dotted;

        -- BR-A04: Nigerian codes have 6 digits, other countries 5; anything else NULL
        UPDATE #addresses_cleaned
        SET postal_code = CASE
                WHEN postal_code LIKE '%[^0-9]%'                              THEN NULL
                WHEN country LIKE 'Nigeria%'     AND LEN(postal_code) = 6     THEN postal_code
                WHEN country NOT LIKE 'Nigeria%' AND LEN(postal_code) = 5     THEN postal_code
                ELSE NULL
            END;

        -------------------------------------------------------------------------
        -- 3) FLAGS
        -------------------------------------------------------------------------
        ALTER TABLE #addresses_cleaned ADD dq_invalid_postal_code BIT NOT NULL DEFAULT 0;

        UPDATE a
        SET dq_invalid_postal_code = 1
        FROM #addresses_cleaned AS a
        JOIN stg.addresses AS s ON s.source_row_number = a.source_row_number
        WHERE a.postal_code IS NULL
          AND ISNULL(UPPER(TRIM(s.postal_code)), '') NOT IN ('', '-', 'NA', 'NULL', 'NONE', 'N/A');

        -------------------------------------------------------------------------
        -- 4) REJECTS: one reason per row, in priority order
        -------------------------------------------------------------------------
        ALTER TABLE #addresses_cleaned ADD reject_rule NVARCHAR(20) NULL, reject_reason NVARCHAR(200) NULL;
        CREATE INDEX ix_addr_customer ON #addresses_cleaned (customer_id);

        -- BR-A06: duplicate address_id
        UPDATE #addresses_cleaned
        SET reject_rule = 'BR-A06', reject_reason = 'Duplicate address_id; first row in file was kept'
        WHERE rn > 1;

        -- BR-A01: the customer must exist
        UPDATE a
        SET reject_rule = 'BR-A01', reject_reason = 'customer_id not found in cln.customers'
        FROM #addresses_cleaned AS a
        WHERE a.reject_rule IS NULL
          AND NOT EXISTS (SELECT 1 FROM cln.customers AS c WHERE c.customer_id = a.customer_id);

        -- BR-A02: exactly one default address per customer
        --         (the lowest address_id among the defaults, or the lowest overall if there is none)
        WITH ranked AS (
            SELECT is_default,
                   ROW_NUMBER() OVER (PARTITION BY customer_id
                                      ORDER BY CASE WHEN is_default = 1 THEN 0 ELSE 1 END, address_id) AS pick
            FROM #addresses_cleaned
            WHERE reject_rule IS NULL
        )
        UPDATE ranked
        SET is_default = CASE WHEN pick = 1 THEN 1 ELSE 0 END;

        DELETE FROM err.rejected_rows WHERE table_name = 'addresses';

        INSERT INTO err.rejected_rows (load_id, table_name, source_row_number, record_key, rule_id, reason)
        SELECT load_id, 'addresses', source_row_number, address_id, reject_rule, reject_reason
        FROM #addresses_cleaned
        WHERE reject_rule IS NOT NULL;

        -------------------------------------------------------------------------
        -- 5) LOAD
        -------------------------------------------------------------------------
        DELETE FROM cln.addresses;

        INSERT INTO cln.addresses
            (address_id, customer_id, address_line, city, state, postal_code, country,
             address_type, is_default, dq_invalid_postal_code, load_id, source_row_number)
        SELECT
             address_id, customer_id, address_line, city, state, postal_code, country,
             address_type, is_default, dq_invalid_postal_code, load_id, source_row_number
        FROM #addresses_cleaned
        WHERE reject_rule IS NULL;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        THROW;
    END CATCH
END;
GO
