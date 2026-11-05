-- Part 2 · Step 4 — prove the star against the normalized copy. Run each query on its own (cursor in it, Cmd+Enter).
-- Every row must say MATCH / 0. These are also the Part 3 business questions: revenue by month, by category, by store.
USE ROLE SYSADMIN;
USE WAREHOUSE CLASS_WH;
USE SCHEMA SAKILA.DW;

-- 1) the star is complete: rows, revenue, and no fact row pointing at a missing dimension row (FKs are not enforced)
SELECT 'fact rows = OLTP payments' AS check_name, (SELECT COUNT(*) FROM FACT_PAYMENT)::VARCHAR AS star, (SELECT COUNT(*) FROM SAKILA.OLTP.PAYMENT)::VARCHAR AS oltp
UNION ALL SELECT 'revenue',                     (SELECT SUM(amount) FROM FACT_PAYMENT)::VARCHAR, (SELECT SUM(amount) FROM SAKILA.OLTP.PAYMENT)::VARCHAR
UNION ALL SELECT 'payment_id unique in fact',   (SELECT COUNT(*) - COUNT(DISTINCT payment_id) FROM FACT_PAYMENT)::VARCHAR, '0'
UNION ALL SELECT 'current customers',           (SELECT COUNT_IF(is_current) FROM DIM_CUSTOMER)::VARCHAR, (SELECT COUNT(*) FROM SAKILA.OLTP.CUSTOMER)::VARCHAR
UNION ALL SELECT 'current films',               (SELECT COUNT_IF(is_current) FROM DIM_FILM)::VARCHAR, (SELECT COUNT(*) FROM SAKILA.OLTP.FILM)::VARCHAR
UNION ALL SELECT 'customers with != 1 current version', (SELECT COUNT(*) FROM (SELECT customer_id FROM DIM_CUSTOMER GROUP BY customer_id HAVING COUNT_IF(is_current) <> 1))::VARCHAR, '0'
UNION ALL SELECT 'films with != 1 current version',     (SELECT COUNT(*) FROM (SELECT film_id FROM DIM_FILM GROUP BY film_id HAVING COUNT_IF(is_current) <> 1))::VARCHAR, '0'
UNION ALL SELECT 'fact rows with no customer',  (SELECT COUNT(*) FROM FACT_PAYMENT f LEFT JOIN DIM_CUSTOMER d ON d.customer_sk = f.customer_sk WHERE d.customer_sk IS NULL)::VARCHAR, '0'
UNION ALL SELECT 'fact rows with no film',      (SELECT COUNT(*) FROM FACT_PAYMENT f LEFT JOIN DIM_FILM d ON d.film_sk = f.film_sk WHERE d.film_sk IS NULL)::VARCHAR, '0'
UNION ALL SELECT 'fact rows with no store',     (SELECT COUNT(*) FROM FACT_PAYMENT f LEFT JOIN DIM_STORE d ON d.store_key = f.store_key WHERE d.store_key IS NULL)::VARCHAR, '0'
UNION ALL SELECT 'fact rows with no date',      (SELECT COUNT(*) FROM FACT_PAYMENT f LEFT JOIN DIM_DATE d ON d.date_key = f.payment_date_key WHERE d.date_key IS NULL)::VARCHAR, '0';
-- expect star = oltp on every row (16044 · 67406.56 · 0 · 599 · 1000 · 0 · 0 · 0 · 0 · 0 · 0)

-- 2) revenue by month — star vs OLTP
WITH star AS (
  SELECT d.year_month, SUM(f.amount) AS revenue FROM FACT_PAYMENT f JOIN DIM_DATE d ON d.date_key = f.payment_date_key GROUP BY 1
), oltp AS (
  SELECT TO_CHAR(payment_date, 'YYYY-MM') AS year_month, SUM(amount) AS revenue FROM SAKILA.OLTP.PAYMENT GROUP BY 1
)
SELECT COALESCE(s.year_month, o.year_month) AS year_month, s.revenue AS star_revenue, o.revenue AS oltp_revenue,
       IFF(s.revenue = o.revenue, 'MATCH', 'DIFF') AS result
FROM star s FULL OUTER JOIN oltp o ON o.year_month = s.year_month ORDER BY 1;

-- 3) revenue by film category — star vs OLTP (OLTP needs payment → rental → inventory → film_category → category)
WITH star AS (
  SELECT df.category, SUM(f.amount) AS revenue FROM FACT_PAYMENT f JOIN DIM_FILM df ON df.film_sk = f.film_sk GROUP BY 1
), oltp AS (
  SELECT c.name AS category, SUM(p.amount) AS revenue
  FROM SAKILA.OLTP.PAYMENT p
  JOIN SAKILA.OLTP.RENTAL r         ON r.rental_id     = p.rental_id
  JOIN SAKILA.OLTP.INVENTORY i      ON i.inventory_id  = r.inventory_id
  JOIN SAKILA.OLTP.FILM_CATEGORY fc ON fc.film_id      = i.film_id
  JOIN SAKILA.OLTP.CATEGORY c       ON c.category_id   = fc.category_id
  GROUP BY 1
)
SELECT COALESCE(s.category, o.category) AS category, s.revenue AS star_revenue, o.revenue AS oltp_revenue,
       IFF(s.revenue = o.revenue, 'MATCH', 'DIFF') AS result
FROM star s FULL OUTER JOIN oltp o ON o.category = s.category ORDER BY star_revenue DESC;

-- 4) revenue by store (store = the store that owns the rented copy) — star vs OLTP
WITH star AS (
  SELECT ds.store_name, f.store_key, SUM(f.amount) AS revenue FROM FACT_PAYMENT f JOIN DIM_STORE ds ON ds.store_key = f.store_key GROUP BY 1, 2
), oltp AS (
  SELECT i.store_id, SUM(p.amount) AS revenue
  FROM SAKILA.OLTP.PAYMENT p
  JOIN SAKILA.OLTP.RENTAL r    ON r.rental_id    = p.rental_id
  JOIN SAKILA.OLTP.INVENTORY i ON i.inventory_id = r.inventory_id
  GROUP BY 1
)
SELECT s.store_name, s.revenue AS star_revenue, o.revenue AS oltp_revenue, IFF(s.revenue = o.revenue, 'MATCH', 'DIFF') AS result
FROM star s FULL OUTER JOIN oltp o ON o.store_id = s.store_key ORDER BY 1;
