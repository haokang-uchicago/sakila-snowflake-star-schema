-- Part 1 · Step 5 — prove the copy is faithful. Every check below must come back MATCH (or 0 problems).
-- Source numbers come from the Cloud SQL export: data/sakila_csv/_source_counts.csv (exact COUNT(*) per table)
-- and, for the value checks, from the exported CSVs themselves (their line counts equal the source counts).
-- Snowflake does not enforce PRIMARY / FOREIGN KEY, so checks 2 and 3 are the only proof the keys survived.
USE ROLE SYSADMIN;
USE WAREHOUSE CLASS_WH;
USE SCHEMA SAKILA.OLTP;

-- 1) row-count parity, table by table — this is the row-count table for the write-up
WITH source (tbl, source_rows) AS (
  SELECT * FROM VALUES
    ('actor', 200),
    ('address', 603),
    ('category', 16),
    ('city', 600),
    ('country', 109),
    ('customer', 599),
    ('film', 1000),
    ('film_actor', 5462),
    ('film_category', 1000),
    ('film_text', 1000),
    ('inventory', 4581),
    ('language', 6),
    ('payment', 16044),
    ('rental', 16044),
    ('staff', 2),
    ('store', 2)
), snowflake (tbl, snowflake_rows) AS (
  SELECT 'actor', COUNT(*) FROM actor
  UNION ALL SELECT 'address', COUNT(*) FROM address
  UNION ALL SELECT 'category', COUNT(*) FROM category
  UNION ALL SELECT 'city', COUNT(*) FROM city
  UNION ALL SELECT 'country', COUNT(*) FROM country
  UNION ALL SELECT 'customer', COUNT(*) FROM customer
  UNION ALL SELECT 'film', COUNT(*) FROM film
  UNION ALL SELECT 'film_actor', COUNT(*) FROM film_actor
  UNION ALL SELECT 'film_category', COUNT(*) FROM film_category
  UNION ALL SELECT 'film_text', COUNT(*) FROM film_text
  UNION ALL SELECT 'inventory', COUNT(*) FROM inventory
  UNION ALL SELECT 'language', COUNT(*) FROM language
  UNION ALL SELECT 'payment', COUNT(*) FROM payment
  UNION ALL SELECT 'rental', COUNT(*) FROM rental
  UNION ALL SELECT 'staff', COUNT(*) FROM staff
  UNION ALL SELECT 'store', COUNT(*) FROM store
)
SELECT * FROM (
  SELECT tbl, source_rows, snowflake_rows, IFF(source_rows = snowflake_rows, 'MATCH', 'DIFF') AS result
  FROM source JOIN snowflake USING (tbl)
  UNION ALL
  SELECT 'TOTAL', SUM(source_rows), SUM(snowflake_rows), IFF(SUM(source_rows) = SUM(snowflake_rows), 'MATCH', 'DIFF')
  FROM source JOIN snowflake USING (tbl)
) ORDER BY IFF(tbl = 'TOTAL', 1, 0), tbl;
-- expect 16 x MATCH and TOTAL 47268 = 47268

-- 2) primary keys are still unique (duplicates = rows - distinct keys, must be 0)
SELECT 'actor' AS tbl, COUNT(*) - COUNT(DISTINCT actor_id) AS duplicate_keys FROM actor
UNION ALL SELECT 'address' AS tbl, COUNT(*) - COUNT(DISTINCT address_id) AS duplicate_keys FROM address
UNION ALL SELECT 'category' AS tbl, COUNT(*) - COUNT(DISTINCT category_id) AS duplicate_keys FROM category
UNION ALL SELECT 'city' AS tbl, COUNT(*) - COUNT(DISTINCT city_id) AS duplicate_keys FROM city
UNION ALL SELECT 'country' AS tbl, COUNT(*) - COUNT(DISTINCT country_id) AS duplicate_keys FROM country
UNION ALL SELECT 'customer' AS tbl, COUNT(*) - COUNT(DISTINCT customer_id) AS duplicate_keys FROM customer
UNION ALL SELECT 'film' AS tbl, COUNT(*) - COUNT(DISTINCT film_id) AS duplicate_keys FROM film
UNION ALL SELECT 'film_actor' AS tbl, COUNT(*) - COUNT(DISTINCT actor_id, film_id) AS duplicate_keys FROM film_actor
UNION ALL SELECT 'film_category' AS tbl, COUNT(*) - COUNT(DISTINCT film_id, category_id) AS duplicate_keys FROM film_category
UNION ALL SELECT 'film_text' AS tbl, COUNT(*) - COUNT(DISTINCT film_id) AS duplicate_keys FROM film_text
UNION ALL SELECT 'inventory' AS tbl, COUNT(*) - COUNT(DISTINCT inventory_id) AS duplicate_keys FROM inventory
UNION ALL SELECT 'language' AS tbl, COUNT(*) - COUNT(DISTINCT language_id) AS duplicate_keys FROM language
UNION ALL SELECT 'payment' AS tbl, COUNT(*) - COUNT(DISTINCT payment_id) AS duplicate_keys FROM payment
UNION ALL SELECT 'rental' AS tbl, COUNT(*) - COUNT(DISTINCT rental_id) AS duplicate_keys FROM rental
UNION ALL SELECT 'staff' AS tbl, COUNT(*) - COUNT(DISTINCT staff_id) AS duplicate_keys FROM staff
UNION ALL SELECT 'store' AS tbl, COUNT(*) - COUNT(DISTINCT store_id) AS duplicate_keys FROM store
ORDER BY tbl;
-- expect 16 rows, all 0

-- 3) foreign keys: no orphans (a child value with no matching parent row), the 22 relationships from _fks.csv
SELECT 'address.city_id -> city.city_id' AS relationship, COUNT(*) AS orphans FROM address c LEFT JOIN city p ON p.city_id = c.city_id WHERE c.city_id IS NOT NULL AND p.city_id IS NULL
UNION ALL SELECT 'city.country_id -> country.country_id' AS relationship, COUNT(*) AS orphans FROM city c LEFT JOIN country p ON p.country_id = c.country_id WHERE c.country_id IS NOT NULL AND p.country_id IS NULL
UNION ALL SELECT 'customer.address_id -> address.address_id' AS relationship, COUNT(*) AS orphans FROM customer c LEFT JOIN address p ON p.address_id = c.address_id WHERE c.address_id IS NOT NULL AND p.address_id IS NULL
UNION ALL SELECT 'customer.store_id -> store.store_id' AS relationship, COUNT(*) AS orphans FROM customer c LEFT JOIN store p ON p.store_id = c.store_id WHERE c.store_id IS NOT NULL AND p.store_id IS NULL
UNION ALL SELECT 'film.language_id -> language.language_id' AS relationship, COUNT(*) AS orphans FROM film c LEFT JOIN language p ON p.language_id = c.language_id WHERE c.language_id IS NOT NULL AND p.language_id IS NULL
UNION ALL SELECT 'film.original_language_id -> language.language_id' AS relationship, COUNT(*) AS orphans FROM film c LEFT JOIN language p ON p.language_id = c.original_language_id WHERE c.original_language_id IS NOT NULL AND p.language_id IS NULL
UNION ALL SELECT 'film_actor.actor_id -> actor.actor_id' AS relationship, COUNT(*) AS orphans FROM film_actor c LEFT JOIN actor p ON p.actor_id = c.actor_id WHERE c.actor_id IS NOT NULL AND p.actor_id IS NULL
UNION ALL SELECT 'film_actor.film_id -> film.film_id' AS relationship, COUNT(*) AS orphans FROM film_actor c LEFT JOIN film p ON p.film_id = c.film_id WHERE c.film_id IS NOT NULL AND p.film_id IS NULL
UNION ALL SELECT 'film_category.category_id -> category.category_id' AS relationship, COUNT(*) AS orphans FROM film_category c LEFT JOIN category p ON p.category_id = c.category_id WHERE c.category_id IS NOT NULL AND p.category_id IS NULL
UNION ALL SELECT 'film_category.film_id -> film.film_id' AS relationship, COUNT(*) AS orphans FROM film_category c LEFT JOIN film p ON p.film_id = c.film_id WHERE c.film_id IS NOT NULL AND p.film_id IS NULL
UNION ALL SELECT 'inventory.film_id -> film.film_id' AS relationship, COUNT(*) AS orphans FROM inventory c LEFT JOIN film p ON p.film_id = c.film_id WHERE c.film_id IS NOT NULL AND p.film_id IS NULL
UNION ALL SELECT 'inventory.store_id -> store.store_id' AS relationship, COUNT(*) AS orphans FROM inventory c LEFT JOIN store p ON p.store_id = c.store_id WHERE c.store_id IS NOT NULL AND p.store_id IS NULL
UNION ALL SELECT 'payment.customer_id -> customer.customer_id' AS relationship, COUNT(*) AS orphans FROM payment c LEFT JOIN customer p ON p.customer_id = c.customer_id WHERE c.customer_id IS NOT NULL AND p.customer_id IS NULL
UNION ALL SELECT 'payment.rental_id -> rental.rental_id' AS relationship, COUNT(*) AS orphans FROM payment c LEFT JOIN rental p ON p.rental_id = c.rental_id WHERE c.rental_id IS NOT NULL AND p.rental_id IS NULL
UNION ALL SELECT 'payment.staff_id -> staff.staff_id' AS relationship, COUNT(*) AS orphans FROM payment c LEFT JOIN staff p ON p.staff_id = c.staff_id WHERE c.staff_id IS NOT NULL AND p.staff_id IS NULL
UNION ALL SELECT 'rental.customer_id -> customer.customer_id' AS relationship, COUNT(*) AS orphans FROM rental c LEFT JOIN customer p ON p.customer_id = c.customer_id WHERE c.customer_id IS NOT NULL AND p.customer_id IS NULL
UNION ALL SELECT 'rental.inventory_id -> inventory.inventory_id' AS relationship, COUNT(*) AS orphans FROM rental c LEFT JOIN inventory p ON p.inventory_id = c.inventory_id WHERE c.inventory_id IS NOT NULL AND p.inventory_id IS NULL
UNION ALL SELECT 'rental.staff_id -> staff.staff_id' AS relationship, COUNT(*) AS orphans FROM rental c LEFT JOIN staff p ON p.staff_id = c.staff_id WHERE c.staff_id IS NOT NULL AND p.staff_id IS NULL
UNION ALL SELECT 'staff.address_id -> address.address_id' AS relationship, COUNT(*) AS orphans FROM staff c LEFT JOIN address p ON p.address_id = c.address_id WHERE c.address_id IS NOT NULL AND p.address_id IS NULL
UNION ALL SELECT 'staff.store_id -> store.store_id' AS relationship, COUNT(*) AS orphans FROM staff c LEFT JOIN store p ON p.store_id = c.store_id WHERE c.store_id IS NOT NULL AND p.store_id IS NULL
UNION ALL SELECT 'store.address_id -> address.address_id' AS relationship, COUNT(*) AS orphans FROM store c LEFT JOIN address p ON p.address_id = c.address_id WHERE c.address_id IS NOT NULL AND p.address_id IS NULL
UNION ALL SELECT 'store.manager_staff_id -> staff.staff_id' AS relationship, COUNT(*) AS orphans FROM store c LEFT JOIN staff p ON p.staff_id = c.manager_staff_id WHERE c.manager_staff_id IS NOT NULL AND p.staff_id IS NULL
ORDER BY relationship;
-- expect 22 rows, all 0

-- 4) the type decisions held: values that came through a conversion, against the same numbers counted in the exported CSVs
SELECT 'payment SUM(amount)'                   AS check_name, (SELECT SUM(amount) FROM payment)::VARCHAR AS snowflake, '67406.56' AS source UNION ALL
SELECT 'payment MIN(payment_date)',  (SELECT MIN(payment_date) FROM payment)::VARCHAR, '2005-05-24 22:53:30.000' UNION ALL
SELECT 'payment MAX(payment_date)',  (SELECT MAX(payment_date) FROM payment)::VARCHAR, '2006-02-14 15:16:03.000' UNION ALL
SELECT 'rental return_date IS NULL', (SELECT COUNT(*) FROM rental WHERE return_date IS NULL)::VARCHAR, '183' UNION ALL
SELECT 'address address2 IS NULL',   (SELECT COUNT(*) FROM address WHERE address2 IS NULL)::VARCHAR, '4' UNION ALL
SELECT 'address address2 = empty',   (SELECT COUNT(*) FROM address WHERE address2 = '')::VARCHAR, '599' UNION ALL
SELECT 'customer active = FALSE',    (SELECT COUNT(*) FROM customer WHERE NOT active)::VARCHAR, '15' UNION ALL
SELECT 'film SUM(rental_rate)',      (SELECT SUM(rental_rate) FROM film)::VARCHAR, '2980.00' UNION ALL
SELECT 'film release_year distinct', (SELECT LISTAGG(DISTINCT release_year, ',') FROM film)::VARCHAR, '2006' UNION ALL
SELECT 'film rating outside ENUM',   (SELECT COUNT(*) FROM film WHERE rating NOT IN ('G','PG','PG-13','R','NC-17'))::VARCHAR, '0' UNION ALL
SELECT 'film special_features outside SET',
  (SELECT COUNT(*) FROM film, LATERAL FLATTEN(INPUT => SPLIT(special_features, ',')) f
   WHERE f.value::VARCHAR NOT IN ('Trailers','Commentaries','Deleted Scenes','Behind the Scenes'))::VARCHAR, '0' UNION ALL
SELECT 'staff picture bytes (staff 1)', (SELECT LENGTH(picture) FROM staff WHERE staff_id = 1)::VARCHAR, '36365' UNION ALL
SELECT 'staff picture is a PNG',     (SELECT LEFT(HEX_ENCODE(picture), 8) FROM staff WHERE staff_id = 1), '89504E47';
-- expect snowflake = source on every row
