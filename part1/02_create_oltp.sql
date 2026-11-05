-- Part 1 · Step 2 — the normalized copy of Sakila in Snowflake: SAKILA.OLTP, 16 tables, same columns in the same order.
-- Run in a Snowsight worksheet (Run All). Re-runnable: CREATE OR REPLACE rebuilds every table empty.
-- Column types come from the source's information_schema.columns (data/sakila_csv/_columns.csv).
--
-- Type decisions (MySQL -> Snowflake):
--   tinyint/smallint/mediumint/int (unsigned) -> INTEGER   Snowflake has no unsigned or small ints; INTEGER = NUMBER(38,0), stored compressed
--   tinyint(1)                                -> BOOLEAN   it is a yes/no flag (customer.active, staff.active); 1/0 load as TRUE/FALSE
--   datetime, timestamp                       -> TIMESTAMP_NTZ  the CSV has no zone; don't invent one
--   year                                      -> NUMBER(4,0)    a number, not a date
--   enum('G','PG',...)                        -> VARCHAR(5)     no ENUM in Snowflake; allowed values are checked by a query in 05_parity.sql
--   set('Trailers',...)                       -> VARCHAR(100)   kept as the original comma list so the copy stays faithful; split into an ARRAY in the DW
--   text                                      -> VARCHAR        unbounded text
--   char(20)                                  -> VARCHAR(20)    MySQL already strips CHAR padding on export
--   geometry                                  -> VARCHAR        exported as WKT text, e.g. POINT(-112.8 49.7)
--   blob                                      -> BINARY         exported as hex; the file format reads hex into bytes
-- Keys: Snowflake records PRIMARY KEY / UNIQUE / FOREIGN KEY but does NOT enforce them (only NOT NULL is enforced),
-- so 05_parity.sql proves them with queries. Foreign keys are added at the end because store and staff reference each other.

-- Same role and warehouse as the Week 4 kit (sql/01_classicmodels_oltp.sql), so the kit's 03_claude_agent.sql grants and
-- setup_agent.sh connection work for SAKILA unchanged apart from the database name.
USE ROLE SYSADMIN;
CREATE WAREHOUSE IF NOT EXISTS CLASS_WH
  WAREHOUSE_SIZE = XSMALL AUTO_SUSPEND = 60 AUTO_RESUME = TRUE INITIALLY_SUSPENDED = TRUE;
ALTER WAREHOUSE CLASS_WH SET AUTO_SUSPEND = 60;
USE WAREHOUSE CLASS_WH;
CREATE DATABASE IF NOT EXISTS SAKILA;
CREATE SCHEMA IF NOT EXISTS SAKILA.OLTP;
USE SCHEMA SAKILA.OLTP;

CREATE OR REPLACE TABLE actor (
  actor_id     INTEGER       NOT NULL PRIMARY KEY,
  first_name   VARCHAR(45)   NOT NULL,
  last_name    VARCHAR(45)   NOT NULL,
  last_update  TIMESTAMP_NTZ NOT NULL
);

CREATE OR REPLACE TABLE address (
  address_id   INTEGER       NOT NULL PRIMARY KEY,
  address      VARCHAR(50)   NOT NULL,
  address2     VARCHAR(50),
  district     VARCHAR(20)   NOT NULL,
  city_id      INTEGER       NOT NULL,
  postal_code  VARCHAR(10),
  phone        VARCHAR(20)   NOT NULL,
  location     VARCHAR       NOT NULL COMMENT 'MySQL GEOMETRY, loaded as WKT text',
  last_update  TIMESTAMP_NTZ NOT NULL
);

CREATE OR REPLACE TABLE category (
  category_id  INTEGER       NOT NULL PRIMARY KEY,
  name         VARCHAR(25)   NOT NULL,
  last_update  TIMESTAMP_NTZ NOT NULL
);

CREATE OR REPLACE TABLE city (
  city_id      INTEGER       NOT NULL PRIMARY KEY,
  city         VARCHAR(50)   NOT NULL,
  country_id   INTEGER       NOT NULL,
  last_update  TIMESTAMP_NTZ NOT NULL
);

CREATE OR REPLACE TABLE country (
  country_id   INTEGER       NOT NULL PRIMARY KEY,
  country      VARCHAR(50)   NOT NULL,
  last_update  TIMESTAMP_NTZ NOT NULL
);

CREATE OR REPLACE TABLE customer (
  customer_id  INTEGER       NOT NULL PRIMARY KEY,
  store_id     INTEGER       NOT NULL,
  first_name   VARCHAR(45)   NOT NULL,
  last_name    VARCHAR(45)   NOT NULL,
  email        VARCHAR(50),
  address_id   INTEGER       NOT NULL,
  active       BOOLEAN       NOT NULL COMMENT 'MySQL TINYINT(1)',
  create_date  TIMESTAMP_NTZ NOT NULL,
  last_update  TIMESTAMP_NTZ
);

CREATE OR REPLACE TABLE film (
  film_id              INTEGER       NOT NULL PRIMARY KEY,
  title                VARCHAR(128)  NOT NULL,
  description          VARCHAR,
  release_year         NUMBER(4,0)            COMMENT 'MySQL YEAR',
  language_id          INTEGER       NOT NULL,
  original_language_id INTEGER,
  rental_duration      INTEGER       NOT NULL,
  rental_rate          NUMBER(4,2)   NOT NULL,
  length               INTEGER,
  replacement_cost     NUMBER(5,2)   NOT NULL,
  rating               VARCHAR(5)             COMMENT 'MySQL ENUM(G,PG,PG-13,R,NC-17)',
  special_features     VARCHAR(100)           COMMENT 'MySQL SET, comma-separated list',
  last_update          TIMESTAMP_NTZ NOT NULL
);

CREATE OR REPLACE TABLE film_actor (
  actor_id     INTEGER       NOT NULL,
  film_id      INTEGER       NOT NULL,
  last_update  TIMESTAMP_NTZ NOT NULL,
  PRIMARY KEY (actor_id, film_id)
);

CREATE OR REPLACE TABLE film_category (
  film_id      INTEGER       NOT NULL,
  category_id  INTEGER       NOT NULL,
  last_update  TIMESTAMP_NTZ NOT NULL,
  PRIMARY KEY (film_id, category_id)
);

CREATE OR REPLACE TABLE film_text (
  film_id      INTEGER       NOT NULL PRIMARY KEY,
  title        VARCHAR(255)  NOT NULL,
  description  VARCHAR
);

CREATE OR REPLACE TABLE inventory (
  inventory_id INTEGER       NOT NULL PRIMARY KEY,
  film_id      INTEGER       NOT NULL,
  store_id     INTEGER       NOT NULL,
  last_update  TIMESTAMP_NTZ NOT NULL
);

CREATE OR REPLACE TABLE language (
  language_id  INTEGER       NOT NULL PRIMARY KEY,
  name         VARCHAR(20)   NOT NULL,
  last_update  TIMESTAMP_NTZ NOT NULL
);

CREATE OR REPLACE TABLE payment (
  payment_id   INTEGER       NOT NULL PRIMARY KEY,
  customer_id  INTEGER       NOT NULL,
  staff_id     INTEGER       NOT NULL,
  rental_id    INTEGER,
  amount       NUMBER(5,2)   NOT NULL,
  payment_date TIMESTAMP_NTZ NOT NULL,
  last_update  TIMESTAMP_NTZ
);

CREATE OR REPLACE TABLE rental (
  rental_id    INTEGER       NOT NULL PRIMARY KEY,
  rental_date  TIMESTAMP_NTZ NOT NULL,
  inventory_id INTEGER       NOT NULL,
  customer_id  INTEGER       NOT NULL,
  return_date  TIMESTAMP_NTZ,
  staff_id     INTEGER       NOT NULL,
  last_update  TIMESTAMP_NTZ NOT NULL
);

CREATE OR REPLACE TABLE staff (
  staff_id     INTEGER       NOT NULL PRIMARY KEY,
  first_name   VARCHAR(45)   NOT NULL,
  last_name    VARCHAR(45)   NOT NULL,
  address_id   INTEGER       NOT NULL,
  picture      BINARY                 COMMENT 'MySQL BLOB, loaded from hex',
  email        VARCHAR(50),
  store_id     INTEGER       NOT NULL,
  active       BOOLEAN       NOT NULL COMMENT 'MySQL TINYINT(1)',
  username     VARCHAR(16)   NOT NULL,
  password     VARCHAR(40),
  last_update  TIMESTAMP_NTZ NOT NULL
);

CREATE OR REPLACE TABLE store (
  store_id         INTEGER       NOT NULL PRIMARY KEY,
  manager_staff_id INTEGER       NOT NULL UNIQUE,
  address_id       INTEGER       NOT NULL,
  last_update      TIMESTAMP_NTZ NOT NULL
);

-- the 22 foreign keys from the source (data/sakila_csv/_fks.csv)
ALTER TABLE address       ADD FOREIGN KEY (city_id)              REFERENCES city (city_id);
ALTER TABLE city          ADD FOREIGN KEY (country_id)           REFERENCES country (country_id);
ALTER TABLE customer      ADD FOREIGN KEY (address_id)           REFERENCES address (address_id);
ALTER TABLE customer      ADD FOREIGN KEY (store_id)             REFERENCES store (store_id);
ALTER TABLE film          ADD FOREIGN KEY (language_id)          REFERENCES language (language_id);
ALTER TABLE film          ADD FOREIGN KEY (original_language_id) REFERENCES language (language_id);
ALTER TABLE film_actor    ADD FOREIGN KEY (actor_id)             REFERENCES actor (actor_id);
ALTER TABLE film_actor    ADD FOREIGN KEY (film_id)              REFERENCES film (film_id);
ALTER TABLE film_category ADD FOREIGN KEY (category_id)          REFERENCES category (category_id);
ALTER TABLE film_category ADD FOREIGN KEY (film_id)              REFERENCES film (film_id);
ALTER TABLE inventory     ADD FOREIGN KEY (film_id)              REFERENCES film (film_id);
ALTER TABLE inventory     ADD FOREIGN KEY (store_id)             REFERENCES store (store_id);
ALTER TABLE payment       ADD FOREIGN KEY (customer_id)          REFERENCES customer (customer_id);
ALTER TABLE payment       ADD FOREIGN KEY (rental_id)            REFERENCES rental (rental_id);
ALTER TABLE payment       ADD FOREIGN KEY (staff_id)             REFERENCES staff (staff_id);
ALTER TABLE rental        ADD FOREIGN KEY (customer_id)          REFERENCES customer (customer_id);
ALTER TABLE rental        ADD FOREIGN KEY (inventory_id)         REFERENCES inventory (inventory_id);
ALTER TABLE rental        ADD FOREIGN KEY (staff_id)             REFERENCES staff (staff_id);
ALTER TABLE staff         ADD FOREIGN KEY (address_id)           REFERENCES address (address_id);
ALTER TABLE staff         ADD FOREIGN KEY (store_id)             REFERENCES store (store_id);
ALTER TABLE store         ADD FOREIGN KEY (address_id)           REFERENCES address (address_id);
ALTER TABLE store         ADD FOREIGN KEY (manager_staff_id)     REFERENCES staff (staff_id);

-- checkpoint: 16 tables, 0 rows each
SELECT table_name, row_count FROM SAKILA.INFORMATION_SCHEMA.TABLES
WHERE table_schema = 'OLTP' ORDER BY table_name;
