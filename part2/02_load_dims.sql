-- Part 2 · Step 2 — load the five dimensions with MERGE. Re-runnable: a second run with no OLTP change inserts 0 and updates 0.
-- Type 1 (DIM_DATE, DIM_STORE, DIM_STAFF): insert new keys, overwrite changed rows in place.
-- Type 2 (DIM_CUSTOMER, DIM_FILM): a changed entity keeps its old row (closed: valid_to = now, is_current = FALSE)
--   and gets a new current row (valid_from = now). Unchanged entities are left alone.
USE ROLE SYSADMIN;
USE WAREHOUSE CLASS_WH;
USE SCHEMA SAKILA.DW;

-- ---------- DIM_DATE: every day 2005-01-01 .. 2006-12-31 (730 rows) ----------
MERGE INTO DIM_DATE d
USING (
  SELECT TO_NUMBER(TO_CHAR(dt, 'YYYYMMDD')) AS date_key, dt AS full_date, YEAR(dt) AS year, QUARTER(dt) AS quarter,
         MONTH(dt) AS month, MONTHNAME(dt) AS month_name, TO_CHAR(dt, 'YYYY-MM') AS year_month,
         DAYOFWEEKISO(dt) AS day_of_week, DAYNAME(dt) AS day_name, DAYOFWEEKISO(dt) IN (6, 7) AS is_weekend
  FROM (SELECT DATEADD(day, ROW_NUMBER() OVER (ORDER BY SEQ4()) - 1, '2005-01-01'::DATE) AS dt
        FROM TABLE(GENERATOR(ROWCOUNT => 730)))
) s
ON d.date_key = s.date_key
WHEN NOT MATCHED THEN INSERT (date_key, full_date, year, quarter, month, month_name, year_month, day_of_week, day_name, is_weekend)
  VALUES (s.date_key, s.full_date, s.year, s.quarter, s.month, s.month_name, s.year_month, s.day_of_week, s.day_name, s.is_weekend);

-- ---------- DIM_STORE (Type 1) ----------
MERGE INTO DIM_STORE d
USING (
  SELECT s.store_id AS store_key, 'Store ' || s.store_id || ' (' || ci.city || ')' AS store_name,
         a.address, a.district, ci.city, co.country, s.manager_staff_id, st.first_name || ' ' || st.last_name AS manager_name
  FROM SAKILA.OLTP.STORE s
  JOIN SAKILA.OLTP.ADDRESS a  ON a.address_id  = s.address_id
  JOIN SAKILA.OLTP.CITY ci    ON ci.city_id    = a.city_id
  JOIN SAKILA.OLTP.COUNTRY co ON co.country_id = ci.country_id
  JOIN SAKILA.OLTP.STAFF st   ON st.staff_id   = s.manager_staff_id
) s
ON d.store_key = s.store_key
WHEN MATCHED AND HASH(d.store_name, d.address, d.district, d.city, d.country, d.manager_staff_id, d.manager_name)
              <> HASH(s.store_name, s.address, s.district, s.city, s.country, s.manager_staff_id, s.manager_name) THEN UPDATE SET
  store_name = s.store_name, address = s.address, district = s.district, city = s.city, country = s.country,
  manager_staff_id = s.manager_staff_id, manager_name = s.manager_name
WHEN NOT MATCHED THEN INSERT (store_key, store_name, address, district, city, country, manager_staff_id, manager_name)
  VALUES (s.store_key, s.store_name, s.address, s.district, s.city, s.country, s.manager_staff_id, s.manager_name);

-- ---------- DIM_STAFF (Type 1) ----------
MERGE INTO DIM_STAFF d
USING (
  SELECT staff_id AS staff_key, first_name || ' ' || last_name AS staff_name, email, store_id, active
  FROM SAKILA.OLTP.STAFF
) s
ON d.staff_key = s.staff_key
WHEN MATCHED AND HASH(d.staff_name, d.email, d.store_id, d.active) <> HASH(s.staff_name, s.email, s.store_id, s.active) THEN UPDATE SET
  staff_name = s.staff_name, email = s.email, store_id = s.store_id, active = s.active
WHEN NOT MATCHED THEN INSERT (staff_key, staff_name, email, store_id, active)
  VALUES (s.staff_key, s.staff_name, s.email, s.store_id, s.active);

-- ---------- DIM_CUSTOMER (SCD Type 2) ----------
-- The source is listed twice:
--   branch 1 (merge_key = customer_id): matches the current version → closes it if the hash changed, else does nothing;
--                                       no match (brand-new customer) → inserts the first version.
--   branch 2 (merge_key = NULL, only customers whose hash changed): never matches → inserts the new current version.
-- First versions start at 1900-01-01, not at load time and not at customer.create_date (2006-02-14 in Sakila, after
-- most 2005 payments): every historical payment must find a version that was valid when it happened.
MERGE INTO DIM_CUSTOMER d
USING (
  SELECT src.customer_id AS merge_key, FALSE AS is_new_version, src.* FROM SAKILA.STAGING.CUSTOMER_SRC src
  UNION ALL
  SELECT NULL, TRUE, src.* FROM SAKILA.STAGING.CUSTOMER_SRC src
  JOIN DIM_CUSTOMER cur ON cur.customer_id = src.customer_id AND cur.is_current AND cur.row_hash <> src.row_hash
) s
ON d.customer_id = s.merge_key AND d.is_current
WHEN MATCHED AND d.row_hash <> s.row_hash THEN UPDATE SET
  valid_to = CURRENT_TIMESTAMP()::TIMESTAMP_NTZ, is_current = FALSE
WHEN NOT MATCHED THEN INSERT (customer_id, first_name, last_name, email, active, home_store_id, address, address2, district,
                              city, country, postal_code, phone, valid_from, valid_to, is_current, row_hash)
  VALUES (s.customer_id, s.first_name, s.last_name, s.email, s.active, s.home_store_id, s.address, s.address2, s.district,
          s.city, s.country, s.postal_code, s.phone,
          IFF(s.is_new_version, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ, '1900-01-01'::TIMESTAMP_NTZ),
          '9999-12-31'::TIMESTAMP_NTZ, TRUE, s.row_hash);

-- ---------- DIM_FILM (SCD Type 2) — same pattern ----------
MERGE INTO DIM_FILM d
USING (
  SELECT src.film_id AS merge_key, FALSE AS is_new_version, src.* FROM SAKILA.STAGING.FILM_SRC src
  UNION ALL
  SELECT NULL, TRUE, src.* FROM SAKILA.STAGING.FILM_SRC src
  JOIN DIM_FILM cur ON cur.film_id = src.film_id AND cur.is_current AND cur.row_hash <> src.row_hash
) s
ON d.film_id = s.merge_key AND d.is_current
WHEN MATCHED AND d.row_hash <> s.row_hash THEN UPDATE SET
  valid_to = CURRENT_TIMESTAMP()::TIMESTAMP_NTZ, is_current = FALSE
WHEN NOT MATCHED THEN INSERT (film_id, title, category, rating, rental_rate, rental_duration, replacement_cost, length,
                              release_year, language, special_features, valid_from, valid_to, is_current, row_hash)
  VALUES (s.film_id, s.title, s.category, s.rating, s.rental_rate, s.rental_duration, s.replacement_cost, s.length,
          s.release_year, s.language, s.special_features,
          IFF(s.is_new_version, CURRENT_TIMESTAMP()::TIMESTAMP_NTZ, '1900-01-01'::TIMESTAMP_NTZ),
          '9999-12-31'::TIMESTAMP_NTZ, TRUE, s.row_hash);

-- checkpoint: rows per dimension (first load: date 730 · store 2 · staff 2 · customer 599 · film 1000; all versions current)
SELECT 'DIM_DATE' AS dim, COUNT(*) AS all_rows, COUNT(*) AS current_rows FROM DIM_DATE
UNION ALL SELECT 'DIM_STORE', COUNT(*), COUNT(*) FROM DIM_STORE
UNION ALL SELECT 'DIM_STAFF', COUNT(*), COUNT(*) FROM DIM_STAFF
UNION ALL SELECT 'DIM_CUSTOMER', COUNT(*), COUNT_IF(is_current) FROM DIM_CUSTOMER
UNION ALL SELECT 'DIM_FILM', COUNT(*), COUNT_IF(is_current) FROM DIM_FILM;
