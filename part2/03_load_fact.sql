-- Part 2 · Step 3 — load FACT_PAYMENT with MERGE on the grain key (payment_id). Run after 02_load_dims.sql.
-- Re-runnable: a payment already in the fact is updated only if something about it changed; nothing is inserted twice.
-- Point-in-time lookups pick the dimension version that was valid when the event happened:
--   customer version valid at payment_ts, film version valid at rental_ts  (valid_from <= ts < valid_to).
-- So a customer who moves later does not drag their old payments to the new address.
USE ROLE SYSADMIN;
USE WAREHOUSE CLASS_WH;
USE SCHEMA SAKILA.DW;

MERGE INTO FACT_PAYMENT f
USING (
  SELECT p.payment_id, p.rental_id,
         TO_NUMBER(TO_CHAR(p.payment_date, 'YYYYMMDD')) AS payment_date_key,
         TO_NUMBER(TO_CHAR(r.rental_date,  'YYYYMMDD')) AS rental_date_key,
         dc.customer_sk, df.film_sk,
         i.store_id AS store_key,                   -- the store that owns the copy (your choice of "store")
         p.staff_id AS staff_key,                   -- who took the payment
         p.amount,
         DATEDIFF(day, r.rental_date, r.return_date) AS rental_days,
         p.payment_date AS payment_ts, r.rental_date AS rental_ts, r.return_date AS return_ts
  FROM SAKILA.OLTP.PAYMENT p
  JOIN SAKILA.OLTP.RENTAL r     ON r.rental_id    = p.rental_id
  JOIN SAKILA.OLTP.INVENTORY i  ON i.inventory_id = r.inventory_id
  JOIN DIM_CUSTOMER dc ON dc.customer_id = p.customer_id AND p.payment_date >= dc.valid_from AND p.payment_date < dc.valid_to
  JOIN DIM_FILM df     ON df.film_id     = i.film_id     AND r.rental_date  >= df.valid_from AND r.rental_date  < df.valid_to
) s
ON f.payment_id = s.payment_id
WHEN MATCHED AND HASH(f.rental_id, f.payment_date_key, f.rental_date_key, f.customer_sk, f.film_sk, f.store_key, f.staff_key,
                      f.amount, f.rental_days, f.payment_ts, f.rental_ts, f.return_ts)
              <> HASH(s.rental_id, s.payment_date_key, s.rental_date_key, s.customer_sk, s.film_sk, s.store_key, s.staff_key,
                      s.amount, s.rental_days, s.payment_ts, s.rental_ts, s.return_ts) THEN UPDATE SET
  rental_id = s.rental_id, payment_date_key = s.payment_date_key, rental_date_key = s.rental_date_key,
  customer_sk = s.customer_sk, film_sk = s.film_sk, store_key = s.store_key, staff_key = s.staff_key,
  amount = s.amount, rental_days = s.rental_days, payment_ts = s.payment_ts, rental_ts = s.rental_ts, return_ts = s.return_ts
WHEN NOT MATCHED THEN INSERT (payment_id, rental_id, payment_date_key, rental_date_key, customer_sk, film_sk, store_key, staff_key,
                              amount, rental_days, payment_ts, rental_ts, return_ts)
  VALUES (s.payment_id, s.rental_id, s.payment_date_key, s.rental_date_key, s.customer_sk, s.film_sk, s.store_key, s.staff_key,
          s.amount, s.rental_days, s.payment_ts, s.rental_ts, s.return_ts);

-- checkpoint: the fact must hold every payment and every cent (expect 16044 rows and 67406.56)
SELECT (SELECT COUNT(*)    FROM FACT_PAYMENT)        AS fact_rows,
       (SELECT COUNT(*)    FROM SAKILA.OLTP.PAYMENT) AS oltp_payments,
       (SELECT SUM(amount) FROM FACT_PAYMENT)        AS fact_revenue,
       (SELECT SUM(amount) FROM SAKILA.OLTP.PAYMENT) AS oltp_revenue;
