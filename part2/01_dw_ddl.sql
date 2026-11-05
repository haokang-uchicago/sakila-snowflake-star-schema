-- Part 2 · Step 1 — the star's structure: schema DW (what Streamlit reads) and schema STAGING (views that shape OLTP for the loads).
-- Safe to re-run: tables use CREATE TABLE IF NOT EXISTS so re-running never wipes the SCD2 history.
-- To rebuild the DW from nothing: DROP SCHEMA SAKILA.DW; then run this file and the loads again.
USE ROLE SYSADMIN;
USE WAREHOUSE CLASS_WH;
CREATE SCHEMA IF NOT EXISTS SAKILA.DW      COMMENT = 'star schema built from SAKILA.OLTP';
CREATE SCHEMA IF NOT EXISTS SAKILA.STAGING COMMENT = 'views that shape OLTP rows for the DW MERGE loads';

-- COPY GRANTS: replacing a view creates a new object and would drop the grants on it (CLAUDE_RO lost SELECT on FILM_SRC once).
-- ---------- staging views: one row per business entity, already denormalized, with a hash of the tracked attributes ----------
-- A customer "moves" when its address row changes or it points at another address_id; either way row_hash changes.
CREATE OR REPLACE VIEW SAKILA.STAGING.CUSTOMER_SRC COPY GRANTS AS
SELECT c.customer_id, c.first_name, c.last_name, c.email, c.active, c.store_id AS home_store_id,
       a.address, a.address2, a.district, ci.city, co.country, a.postal_code, a.phone,
       HASH(c.first_name, c.last_name, c.email, c.active, c.store_id,
            a.address, a.address2, a.district, ci.city, co.country, a.postal_code, a.phone) AS row_hash
FROM SAKILA.OLTP.CUSTOMER c
JOIN SAKILA.OLTP.ADDRESS a  ON a.address_id  = c.address_id
JOIN SAKILA.OLTP.CITY ci    ON ci.city_id    = a.city_id
JOIN SAKILA.OLTP.COUNTRY co ON co.country_id = ci.country_id;

-- film_category is many-to-many in the schema; in this data every film has exactly one category (1000 films, 1000 rows).
-- The view keeps ONE category per film (lowest category_id) and keeps films with none as 'Unknown', so DIM_FILM stays
-- one current row per film and the fact never fans out. (A duplicate source row would NOT stop a first-time insert:
-- MERGE only errors when several source rows update the same target row — caught by the grain-reviewer.)
CREATE OR REPLACE VIEW SAKILA.STAGING.FILM_SRC COPY GRANTS AS
WITH fcat AS (
  SELECT fc.film_id, cat.name AS category
  FROM SAKILA.OLTP.FILM_CATEGORY fc
  JOIN SAKILA.OLTP.CATEGORY cat ON cat.category_id = fc.category_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY fc.film_id ORDER BY fc.category_id) = 1
)
SELECT f.film_id, f.title, COALESCE(fcat.category, 'Unknown') AS category, f.rating, f.rental_rate, f.rental_duration,
       f.replacement_cost, f.length, f.release_year, l.name AS language, SPLIT(f.special_features, ',') AS special_features,
       HASH(f.title, COALESCE(fcat.category, 'Unknown'), f.rating, f.rental_rate, f.rental_duration, f.replacement_cost,
            f.length, f.release_year, l.name, f.special_features) AS row_hash
FROM SAKILA.OLTP.FILM f
JOIN SAKILA.OLTP.LANGUAGE l ON l.language_id = f.language_id
LEFT JOIN fcat ON fcat.film_id = f.film_id;

USE SCHEMA SAKILA.DW;

-- ---------- dimensions ----------
CREATE TABLE IF NOT EXISTS DIM_DATE (
  date_key     INTEGER     NOT NULL COMMENT 'YYYYMMDD',
  full_date    DATE        NOT NULL,
  year         INTEGER     NOT NULL,
  quarter      INTEGER     NOT NULL,
  month        INTEGER     NOT NULL,
  month_name   VARCHAR(3)  NOT NULL,
  year_month   VARCHAR(7)  NOT NULL COMMENT 'e.g. 2005-07, for monthly charts',
  day_of_week  INTEGER     NOT NULL COMMENT 'ISO: 1 = Monday',
  day_name     VARCHAR(3)  NOT NULL,
  is_weekend   BOOLEAN     NOT NULL,
  PRIMARY KEY (date_key)
) COMMENT = 'grain: one row per calendar day, 2005-01-01 .. 2006-12-31 (730 days; covers every rental and payment)';

CREATE TABLE IF NOT EXISTS DIM_CUSTOMER (
  customer_sk    INTEGER IDENTITY(1,1) NOT NULL COMMENT 'surrogate key: one per version of a customer',
  customer_id    INTEGER       NOT NULL COMMENT 'natural key = OLTP customer.customer_id',
  first_name     VARCHAR(45)   NOT NULL,
  last_name      VARCHAR(45)   NOT NULL,
  email          VARCHAR(50),
  active         BOOLEAN       NOT NULL,
  home_store_id  INTEGER       NOT NULL COMMENT 'the store the customer is registered at (not the store a rental came from)',
  address        VARCHAR(50)   NOT NULL,
  address2       VARCHAR(50),
  district       VARCHAR(20)   NOT NULL,
  city           VARCHAR(50)   NOT NULL,
  country        VARCHAR(50)   NOT NULL,
  postal_code    VARCHAR(10),
  phone          VARCHAR(20)   NOT NULL,
  valid_from     TIMESTAMP_NTZ NOT NULL COMMENT 'version is valid from this moment (inclusive); first version = 1900-01-01',
  valid_to       TIMESTAMP_NTZ NOT NULL COMMENT 'version is valid until this moment (exclusive); current version = 9999-12-31',
  is_current     BOOLEAN       NOT NULL,
  row_hash       NUMBER(19,0)  NOT NULL COMMENT 'HASH of the tracked attributes; a different hash = a new version',
  PRIMARY KEY (customer_sk)
) COMMENT = 'SCD Type 2 — grain: one row per customer per version of their attributes (address, city, country, home store, name, email, active)';

CREATE TABLE IF NOT EXISTS DIM_FILM (
  film_sk           INTEGER IDENTITY(1,1) NOT NULL COMMENT 'surrogate key: one per version of a film',
  film_id           INTEGER       NOT NULL COMMENT 'natural key = OLTP film.film_id',
  title             VARCHAR(128)  NOT NULL,
  category          VARCHAR(25)   NOT NULL,
  rating            VARCHAR(5),
  rental_rate       NUMBER(4,2)   NOT NULL COMMENT 'price per rental; tracked as Type 2 so old rentals keep the price they were rented at',
  rental_duration   INTEGER       NOT NULL,
  replacement_cost  NUMBER(5,2)   NOT NULL,
  length            INTEGER,
  release_year      NUMBER(4,0),
  language          VARCHAR(20)   NOT NULL,
  special_features  ARRAY                  COMMENT 'MySQL SET split into an array: query with ARRAY_CONTAINS',
  valid_from        TIMESTAMP_NTZ NOT NULL,
  valid_to          TIMESTAMP_NTZ NOT NULL,
  is_current        BOOLEAN       NOT NULL,
  row_hash          NUMBER(19,0)  NOT NULL,
  PRIMARY KEY (film_sk)
) COMMENT = 'SCD Type 2 — grain: one row per film per version of its attributes (rental rate, rating, replacement cost, category, ...)';

CREATE TABLE IF NOT EXISTS DIM_STORE (
  store_key         INTEGER      NOT NULL COMMENT '= OLTP store.store_id (Type 1: overwritten on change)',
  store_name        VARCHAR(80)  NOT NULL,
  address           VARCHAR(50)  NOT NULL,
  district          VARCHAR(20)  NOT NULL,
  city              VARCHAR(50)  NOT NULL,
  country           VARCHAR(50)  NOT NULL,
  manager_staff_id  INTEGER      NOT NULL,
  manager_name      VARCHAR(91)  NOT NULL,
  PRIMARY KEY (store_key)
) COMMENT = 'Type 1 — grain: one row per store';

CREATE TABLE IF NOT EXISTS DIM_STAFF (
  staff_key   INTEGER      NOT NULL COMMENT '= OLTP staff.staff_id (Type 1)',
  staff_name  VARCHAR(91)  NOT NULL,
  email       VARCHAR(50),
  store_id    INTEGER      NOT NULL COMMENT 'the store the staff member works at',
  active      BOOLEAN      NOT NULL,
  PRIMARY KEY (staff_key)
) COMMENT = 'Type 1 — grain: one row per staff member';

-- ---------- fact ----------
CREATE TABLE IF NOT EXISTS FACT_PAYMENT (
  payment_id        INTEGER       NOT NULL COMMENT 'degenerate dimension = OLTP payment.payment_id; one row each — this is the grain',
  rental_id         INTEGER       NOT NULL COMMENT 'degenerate dimension = OLTP rental.rental_id (1:1 with payment in this data)',
  payment_date_key  INTEGER       NOT NULL COMMENT 'day the payment was made',
  rental_date_key   INTEGER       NOT NULL COMMENT 'day the film was rented',
  customer_sk       INTEGER       NOT NULL COMMENT 'customer version valid at payment time',
  film_sk           INTEGER       NOT NULL COMMENT 'film version valid at rental time',
  store_key         INTEGER       NOT NULL COMMENT 'store that owns the rented copy (inventory.store_id)',
  staff_key         INTEGER       NOT NULL COMMENT 'staff member who took the payment',
  amount            NUMBER(5,2)   NOT NULL COMMENT 'measure, additive: revenue = SUM(amount)',
  rental_days       INTEGER                COMMENT 'measure: days from rental to return; NULL while not returned (183 rentals); average it, do not sum it',
  payment_ts        TIMESTAMP_NTZ NOT NULL,
  rental_ts         TIMESTAMP_NTZ NOT NULL,
  return_ts         TIMESTAMP_NTZ,
  PRIMARY KEY (payment_id),
  FOREIGN KEY (payment_date_key) REFERENCES DIM_DATE (date_key),
  FOREIGN KEY (rental_date_key)  REFERENCES DIM_DATE (date_key),
  FOREIGN KEY (customer_sk)      REFERENCES DIM_CUSTOMER (customer_sk),
  FOREIGN KEY (film_sk)          REFERENCES DIM_FILM (film_sk),
  FOREIGN KEY (store_key)        REFERENCES DIM_STORE (store_key),
  FOREIGN KEY (staff_key)        REFERENCES DIM_STAFF (staff_key)
) COMMENT = 'grain: one row per payment (OLTP payment_id). Revenue = SUM(amount) at any slice of date, customer, film, store or staff.';

-- checkpoint: 6 tables in DW, 2 views in STAGING
SELECT table_schema, table_name, table_type, comment FROM SAKILA.INFORMATION_SCHEMA.TABLES
WHERE table_schema IN ('DW', 'STAGING') ORDER BY table_schema, table_name;
