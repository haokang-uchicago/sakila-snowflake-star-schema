-- Part 3 · A question the model answers badly: "which actors bring in the most revenue?"
-- The star has no actor at all. A film has many actors (film_actor is many-to-many), so the obvious fix — join payments
-- to film_actor — counts every payment once per actor in the film and inflates revenue about 5.45x.
-- What I would change: add a bridge table DW.BRIDGE_FILM_ACTOR (film_sk, actor_key, weight = 1 / actors in the film)
-- plus a small DIM_ACTOR, and always multiply amount by weight when slicing by actor (the course slide's "bridge for many-to-many").
USE ROLE SYSADMIN;
USE WAREHOUSE CLASS_WH;

-- 1) the problem: the naive actor join vs the true total (expect 367559.07 vs 67406.56)
SELECT SUM(p.amount) AS revenue_after_actor_join,
       (SELECT SUM(amount) FROM SAKILA.OLTP.PAYMENT) AS true_revenue,
       ROUND(SUM(p.amount) / (SELECT SUM(amount) FROM SAKILA.OLTP.PAYMENT), 2) AS inflation
FROM SAKILA.OLTP.PAYMENT p
JOIN SAKILA.OLTP.RENTAL r      ON r.rental_id    = p.rental_id
JOIN SAKILA.OLTP.INVENTORY i   ON i.inventory_id = r.inventory_id
JOIN SAKILA.OLTP.FILM_ACTOR fa ON fa.film_id     = i.film_id;

-- 2) the fix, sketched: weight each actor by 1 / (actors in the film) — the weighted total adds back up to the truth
WITH w AS (
  SELECT film_id, actor_id, 1 / COUNT(*) OVER (PARTITION BY film_id) AS weight FROM SAKILA.OLTP.FILM_ACTOR
)
SELECT ROUND(SUM(p.amount * w.weight), 2) AS weighted_revenue_over_actors,
       (SELECT SUM(amount) FROM SAKILA.OLTP.PAYMENT) AS true_revenue
FROM SAKILA.OLTP.PAYMENT p
JOIN SAKILA.OLTP.RENTAL r    ON r.rental_id    = p.rental_id
JOIN SAKILA.OLTP.INVENTORY i ON i.inventory_id = r.inventory_id
JOIN w                       ON w.film_id      = i.film_id;
