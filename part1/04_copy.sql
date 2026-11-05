-- Part 1 · Step 4 — load each CSV from the stage into its table. Columns are matched by position, which is why
-- 02_create_oltp.sql keeps the source column order. ON_ERROR = ABORT_STATEMENT: one bad row fails the whole file, loudly.
-- Re-running is safe: COPY remembers which files it already loaded into a table and skips them (no duplicate rows).
-- To load from scratch, re-run 02_create_oltp.sql first (new, empty tables have no load history).
USE ROLE SYSADMIN;
USE WAREHOUSE CLASS_WH;
USE SCHEMA SAKILA.OLTP;

COPY INTO actor         FROM @sakila_stage/actor.csv         FILE_FORMAT = (FORMAT_NAME = 'sakila_csv') ON_ERROR = ABORT_STATEMENT;
COPY INTO address       FROM @sakila_stage/address.csv       FILE_FORMAT = (FORMAT_NAME = 'sakila_csv') ON_ERROR = ABORT_STATEMENT;
COPY INTO category      FROM @sakila_stage/category.csv      FILE_FORMAT = (FORMAT_NAME = 'sakila_csv') ON_ERROR = ABORT_STATEMENT;
COPY INTO city          FROM @sakila_stage/city.csv          FILE_FORMAT = (FORMAT_NAME = 'sakila_csv') ON_ERROR = ABORT_STATEMENT;
COPY INTO country       FROM @sakila_stage/country.csv       FILE_FORMAT = (FORMAT_NAME = 'sakila_csv') ON_ERROR = ABORT_STATEMENT;
COPY INTO customer      FROM @sakila_stage/customer.csv      FILE_FORMAT = (FORMAT_NAME = 'sakila_csv') ON_ERROR = ABORT_STATEMENT;
COPY INTO film          FROM @sakila_stage/film.csv          FILE_FORMAT = (FORMAT_NAME = 'sakila_csv') ON_ERROR = ABORT_STATEMENT;
COPY INTO film_actor    FROM @sakila_stage/film_actor.csv    FILE_FORMAT = (FORMAT_NAME = 'sakila_csv') ON_ERROR = ABORT_STATEMENT;
COPY INTO film_category FROM @sakila_stage/film_category.csv FILE_FORMAT = (FORMAT_NAME = 'sakila_csv') ON_ERROR = ABORT_STATEMENT;
COPY INTO film_text     FROM @sakila_stage/film_text.csv     FILE_FORMAT = (FORMAT_NAME = 'sakila_csv') ON_ERROR = ABORT_STATEMENT;
COPY INTO inventory     FROM @sakila_stage/inventory.csv     FILE_FORMAT = (FORMAT_NAME = 'sakila_csv') ON_ERROR = ABORT_STATEMENT;
COPY INTO language      FROM @sakila_stage/language.csv      FILE_FORMAT = (FORMAT_NAME = 'sakila_csv') ON_ERROR = ABORT_STATEMENT;
COPY INTO payment       FROM @sakila_stage/payment.csv       FILE_FORMAT = (FORMAT_NAME = 'sakila_csv') ON_ERROR = ABORT_STATEMENT;
COPY INTO rental        FROM @sakila_stage/rental.csv        FILE_FORMAT = (FORMAT_NAME = 'sakila_csv') ON_ERROR = ABORT_STATEMENT;
COPY INTO staff         FROM @sakila_stage/staff.csv         FILE_FORMAT = (FORMAT_NAME = 'sakila_csv') ON_ERROR = ABORT_STATEMENT;
COPY INTO store         FROM @sakila_stage/store.csv         FILE_FORMAT = (FORMAT_NAME = 'sakila_csv') ON_ERROR = ABORT_STATEMENT;

-- checkpoint: rows per table straight after the load (05_parity.sql compares them with the source)
SELECT table_name, row_count FROM SAKILA.INFORMATION_SCHEMA.TABLES
WHERE table_schema = 'OLTP' AND table_type = 'BASE TABLE' ORDER BY table_name;
