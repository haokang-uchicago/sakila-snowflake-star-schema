-- Part 3 · Where the normalized copy and the star disagree — run after 01_scd2_history.sql (MARY SMITH moved).
-- Question: revenue by the customer's country.
--   OLTP only knows where a customer lives NOW, so her 32 payments of 2005 (118.68) are counted under United States.
--   The star uses the customer version valid WHEN she paid, so they stay under Japan.
USE ROLE SYSADMIN;
USE WAREHOUSE CLASS_WH;

-- 1) the disagreement: only the countries whose numbers differ, plus the total (the total still matches)
WITH star AS (
  SELECT dc.country, SUM(f.amount) AS revenue
  FROM SAKILA.DW.FACT_PAYMENT f JOIN SAKILA.DW.DIM_CUSTOMER dc ON dc.customer_sk = f.customer_sk
  GROUP BY 1
), oltp AS (
  SELECT co.country, SUM(p.amount) AS revenue
  FROM SAKILA.OLTP.PAYMENT p
  JOIN SAKILA.OLTP.CUSTOMER c ON c.customer_id = p.customer_id
  JOIN SAKILA.OLTP.ADDRESS a  ON a.address_id  = c.address_id
  JOIN SAKILA.OLTP.CITY ci    ON ci.city_id    = a.city_id
  JOIN SAKILA.OLTP.COUNTRY co ON co.country_id = ci.country_id
  GROUP BY 1
), cmp AS (
  SELECT COALESCE(s.country, o.country) AS country, s.revenue AS star_revenue, o.revenue AS oltp_revenue
  FROM star s FULL OUTER JOIN oltp o ON o.country = s.country
)
SELECT country, star_revenue, oltp_revenue, COALESCE(oltp_revenue, 0) - COALESCE(star_revenue, 0) AS oltp_minus_star,
       IFF(star_revenue = oltp_revenue, 'MATCH', 'DIFF') AS result
FROM cmp WHERE star_revenue IS DISTINCT FROM oltp_revenue
UNION ALL
SELECT 'TOTAL (all countries)', SUM(star_revenue), SUM(oltp_revenue), SUM(oltp_revenue) - SUM(star_revenue),
       IFF(SUM(star_revenue) = SUM(oltp_revenue), 'MATCH', 'DIFF')
FROM cmp;
-- expect: Japan star = oltp + 118.68, United States oltp = star + 118.68, TOTAL MATCH 67406.56

-- 2) the deciding query: where did customer 1 live when each of her payments was made?
--    Every payment is from 2005; the move happened in 2026, so all 32 belong to Sasebo, Japan.
SELECT dc.customer_sk, dc.city, dc.country, dc.valid_from, dc.valid_to,
       COUNT(*) AS payments, SUM(f.amount) AS revenue, MIN(f.payment_ts) AS first_payment, MAX(f.payment_ts) AS last_payment
FROM SAKILA.DW.FACT_PAYMENT f JOIN SAKILA.DW.DIM_CUSTOMER dc ON dc.customer_sk = f.customer_sk
WHERE dc.customer_id = 1
GROUP BY ALL;

-- 3) the star can still answer "where do our paying customers live TODAY": join each payment to the CURRENT version
SELECT cur.country, SUM(f.amount) AS revenue
FROM SAKILA.DW.FACT_PAYMENT f
JOIN SAKILA.DW.DIM_CUSTOMER v   ON v.customer_sk  = f.customer_sk
JOIN SAKILA.DW.DIM_CUSTOMER cur ON cur.customer_id = v.customer_id AND cur.is_current
WHERE cur.country IN ('Japan', 'United States')
GROUP BY 1 ORDER BY 1;
-- expect: the same Japan / United States numbers as the OLTP column in query 1

-- 4) the trap: joining the fact to an SCD2 dimension on the NATURAL key multiplies rows (MARY's payments count twice)
SELECT COUNT(*) AS rows_after_join, SUM(f.amount) AS revenue_after_join
FROM SAKILA.DW.FACT_PAYMENT f
JOIN SAKILA.DW.DIM_CUSTOMER v  ON v.customer_sk  = f.customer_sk
JOIN SAKILA.DW.DIM_CUSTOMER dc ON dc.customer_id = v.customer_id;      -- every version of the customer, not just one
-- expect 16076 rows (16044 + 32) and 67525.24 (67406.56 + 118.68): wrong — always join on customer_sk
