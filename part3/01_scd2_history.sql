-- Part 3 · Exercise the history: customer 1 (MARY SMITH) moves from Sasebo, Japan to Joliet, United States.
-- Run the steps in order, one at a time. Step C runs the Part 2 loads again — the same MERGE files, unchanged.
-- Note: this deliberately changes ONE address row in SAKILA.OLTP (it plays the role of the live source system).
USE ROLE SYSADMIN;
USE WAREHOUSE CLASS_WH;

-- Step A — BEFORE: one version of customer 1, and the payments attached to it (expect 1 row, 32 payments, 118.68)
SELECT d.customer_sk, d.customer_id, d.first_name, d.last_name, d.address, d.city, d.country,
       d.valid_from, d.valid_to, d.is_current, COUNT(f.payment_id) AS payments, SUM(f.amount) AS revenue
FROM SAKILA.DW.DIM_CUSTOMER d
LEFT JOIN SAKILA.DW.FACT_PAYMENT f ON f.customer_sk = d.customer_sk
WHERE d.customer_id = 1
GROUP BY ALL ORDER BY d.valid_from;

-- Step B — the customer moves: change her address row in the source (address 5 belongs to customer 1 only)
UPDATE SAKILA.OLTP.ADDRESS
SET address = '233 N Chicago St', district = 'Illinois', city_id = 245, postal_code = '60432'   -- city 245 = Joliet, United States
WHERE address_id = (SELECT address_id FROM SAKILA.OLTP.CUSTOMER WHERE customer_id = 1);

-- the staging view sees the new address immediately, and her row_hash has changed
SELECT customer_id, first_name, last_name, address, city, country, row_hash
FROM SAKILA.STAGING.CUSTOMER_SRC WHERE customer_id = 1;

-- Step C — re-run the loads: Run All part2/02_load_dims.sql, then Run All part2/03_load_fact.sql (unchanged files)

-- Step D — AFTER: two versions. The old one is closed (valid_to = load time, is_current = FALSE) and still holds
-- all 32 payments of 2005; the new one is current and has no payments yet. Expect 2 rows.
SELECT d.customer_sk, d.customer_id, d.first_name, d.last_name, d.address, d.city, d.country,
       d.valid_from, d.valid_to, d.is_current, COUNT(f.payment_id) AS payments, SUM(f.amount) AS revenue
FROM SAKILA.DW.DIM_CUSTOMER d
LEFT JOIN SAKILA.DW.FACT_PAYMENT f ON f.customer_sk = d.customer_sk
WHERE d.customer_id = 1
GROUP BY ALL ORDER BY d.valid_from;
