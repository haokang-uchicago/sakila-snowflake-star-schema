# Data dictionary — SAKILA.DW

Built from `SAKILA.INFORMATION_SCHEMA` on 2026-10-26 via `snow sql -c claude` (role CLAUDE_RO, read-only).
Every fact carries a tag `[Qn]` naming the query that produced it; the full text of each query is under [Queries](#queries).
`[DDL:n]` cites a line in `sql/sakila/part2_01_dw_ddl.sql`, used only where INFORMATION_SCHEMA does not hold the fact.

Notes on reading this:
- **Comment** text is the `COMMENT` stored on the object [Q1][Q2]. It is the author's claim. Unless a row says
  "verified", nobody checked it against the data.
- **Type** is INFORMATION_SCHEMA's spelling [Q2]: `INTEGER` shows up as `NUMBER(38,0)` and `VARCHAR(n)` as `TEXT(n)`.
- **Null?** `NO` means the column is declared NOT NULL. Snowflake does enforce NOT NULL.
- Snowflake **does not enforce** PRIMARY KEY or FOREIGN KEY: every constraint in DW has `ENFORCED = NO` [Q3].
  Uniqueness was checked separately [Q6].

## Summary

| Table | Type | Rows (metadata) [Q1] | COUNT(*) [Q5] | Bytes [Q1] | Columns [Q4] | Nullable cols [Q4] | Identity cols [Q4] | Clustering key [Q1] |
|---|---|---:|---:|---:|---:|---:|---:|---|
| DIM_CUSTOMER | BASE TABLE | 600 | 600 | 53,760 | 18 | 3 | 1 | none |
| DIM_DATE | BASE TABLE | 730 | 730 | 5,632 | 10 | 0 | 0 | none |
| DIM_FILM | BASE TABLE | 1,000 | 1,000 | 36,352 | 16 | 4 | 1 | none |
| DIM_STAFF | BASE TABLE | 2 | 2 | 1,024 | 5 | 1 | 0 | none |
| DIM_STORE | BASE TABLE | 2 | 2 | 1,536 | 8 | 0 | 0 | none |
| FACT_PAYMENT | BASE TABLE | 16,044 | 16,044 | 475,648 | 13 | 2 | 0 | none |

Reconciliation:
- The metadata ROW_COUNT [Q1] matches COUNT(*) [Q5] for all 6 tables.
- `SUM(FACT_PAYMENT.amount)` = **67,406.56** [Q5], the same as the OLTP revenue total.
- Every declared PK is unique, with COUNT(*) = COUNT(DISTINCT pk) on all 6 tables [Q6].
- The per-column listings below match [Q4] on column count, nullable count and identity count for every table.

## Relationships

FACT_PAYMENT declares 6 foreign keys and every dimension declares a primary key [Q3]. None of them is enforced [Q3].
All 6 FKs are `MATCH FULL`, `UPDATE NO ACTION`, `DELETE NO ACTION` [Q7].

| FK column | → Referenced table [Q7] | Referenced column |
|---|---|---|
| payment_date_key | DIM_DATE | date_key [DDL:137] |
| rental_date_key | DIM_DATE | date_key [DDL:138] |
| customer_sk | DIM_CUSTOMER | customer_sk [DDL:139] |
| film_sk | DIM_FILM | film_sk [DDL:140] |
| store_key | DIM_STORE | store_key [DDL:141] |
| staff_key | DIM_STAFF | staff_key [DDL:142] |

[Q7] confirms the target tables, including 2 FKs to DIM_DATE. INFORMATION_SCHEMA has no column-level FK mapping, so the
referenced-column column comes from the DDL.
Join the fact to DIM_CUSTOMER and DIM_FILM on the `_sk` surrogate key, never on `customer_id` / `film_id`. Both are SCD Type 2
[Q1], and joining on the natural key multiplies rows for any entity with more than one version. DIM_CUSTOMER has 600 rows
[Q5] for 599 customers.

---

## FACT_PAYMENT

**Comment** [Q1]: grain: one row per payment (OLTP payment_id). Revenue = SUM(amount) at any slice of date, customer, film, store or staff.
**PK** payment_id [Q3][DDL:136]. **Verified** unique: 16,044 rows / 16,044 distinct [Q6]. **Verified** SUM(amount) = 67,406.56 [Q5].

| # | Column | Type [Q2] | Null? [Q2] | Key | Comment [Q2] |
|---:|---|---|---|---|---|
| 1 | PAYMENT_ID | NUMBER(38,0) | NO | PK | degenerate dimension = OLTP payment.payment_id; one row each — this is the grain |
| 2 | RENTAL_ID | NUMBER(38,0) | NO | | degenerate dimension = OLTP rental.rental_id (1:1 with payment in this data) |
| 3 | PAYMENT_DATE_KEY | NUMBER(38,0) | NO | FK → DIM_DATE | day the payment was made |
| 4 | RENTAL_DATE_KEY | NUMBER(38,0) | NO | FK → DIM_DATE | day the film was rented |
| 5 | CUSTOMER_SK | NUMBER(38,0) | NO | FK → DIM_CUSTOMER | customer version valid at payment time |
| 6 | FILM_SK | NUMBER(38,0) | NO | FK → DIM_FILM | film version valid at rental time |
| 7 | STORE_KEY | NUMBER(38,0) | NO | FK → DIM_STORE | store that owns the rented copy (inventory.store_id) |
| 8 | STAFF_KEY | NUMBER(38,0) | NO | FK → DIM_STAFF | staff member who took the payment |
| 9 | AMOUNT | NUMBER(5,2) | NO | | measure, additive: revenue = SUM(amount) |
| 10 | RENTAL_DAYS | NUMBER(38,0) | YES | | measure: days from rental to return; NULL while not returned (183 rentals); average it, do not sum it |
| 11 | PAYMENT_TS | TIMESTAMP_NTZ | NO | | — |
| 12 | RENTAL_TS | TIMESTAMP_NTZ | NO | | — |
| 13 | RETURN_TS | TIMESTAMP_NTZ | YES | | — |

FK targets are from [Q7] and [DDL:137-142]. The "183 rentals" figure in the RENTAL_DAYS comment was not verified here.

## DIM_CUSTOMER

**Comment** [Q1]: SCD Type 2 — grain: one row per customer per version of their attributes (address, city, country, home store, name, email, active)
**PK** customer_sk [Q3][DDL:77]. **Verified** unique: 600 / 600 [Q6]. customer_sk is an IDENTITY column [Q2].

| # | Column | Type [Q2] | Null? [Q2] | Key | Comment [Q2] |
|---:|---|---|---|---|---|
| 1 | CUSTOMER_SK | NUMBER(38,0) | NO | PK, IDENTITY | surrogate key: one per version of a customer |
| 2 | CUSTOMER_ID | NUMBER(38,0) | NO | natural key | natural key = OLTP customer.customer_id |
| 3 | FIRST_NAME | TEXT(45) | NO | | — |
| 4 | LAST_NAME | TEXT(45) | NO | | — |
| 5 | EMAIL | TEXT(50) | YES | | — |
| 6 | ACTIVE | BOOLEAN | NO | | — |
| 7 | HOME_STORE_ID | NUMBER(38,0) | NO | | the store the customer is registered at (not the store a rental came from) |
| 8 | ADDRESS | TEXT(50) | NO | | — |
| 9 | ADDRESS2 | TEXT(50) | YES | | — |
| 10 | DISTRICT | TEXT(20) | NO | | — |
| 11 | CITY | TEXT(50) | NO | | — |
| 12 | COUNTRY | TEXT(50) | NO | | — |
| 13 | POSTAL_CODE | TEXT(10) | YES | | — |
| 14 | PHONE | TEXT(20) | NO | | — |
| 15 | VALID_FROM | TIMESTAMP_NTZ | NO | SCD2 | version is valid from this moment (inclusive); first version = 1900-01-01 |
| 16 | VALID_TO | TIMESTAMP_NTZ | NO | SCD2 | version is valid until this moment (exclusive); current version = 9999-12-31 |
| 17 | IS_CURRENT | BOOLEAN | NO | SCD2 | — |
| 18 | ROW_HASH | NUMBER(19,0) | NO | SCD2 | HASH of the tracked attributes; a different hash = a new version |

HOME_STORE_ID is not a declared FK [Q3]. The fact's store_key (the copy's store) is the column that joins to DIM_STORE.

## DIM_FILM

**Comment** [Q1]: SCD Type 2 — grain: one row per film per version of its attributes (rental rate, rating, replacement cost, category, ...)
**PK** film_sk [Q3][DDL:97]. **Verified** unique: 1,000 / 1,000 [Q6]. film_sk is an IDENTITY column [Q2].

| # | Column | Type [Q2] | Null? [Q2] | Key | Comment [Q2] |
|---:|---|---|---|---|---|
| 1 | FILM_SK | NUMBER(38,0) | NO | PK, IDENTITY | surrogate key: one per version of a film |
| 2 | FILM_ID | NUMBER(38,0) | NO | natural key | natural key = OLTP film.film_id |
| 3 | TITLE | TEXT(128) | NO | | — |
| 4 | CATEGORY | TEXT(25) | NO | | — |
| 5 | RATING | TEXT(5) | YES | | — |
| 6 | RENTAL_RATE | NUMBER(4,2) | NO | | price per rental; tracked as Type 2 so old rentals keep the price they were rented at |
| 7 | RENTAL_DURATION | NUMBER(38,0) | NO | | — |
| 8 | REPLACEMENT_COST | NUMBER(5,2) | NO | | — |
| 9 | LENGTH | NUMBER(38,0) | YES | | — |
| 10 | RELEASE_YEAR | NUMBER(4,0) | YES | | — |
| 11 | LANGUAGE | TEXT(20) | NO | | — |
| 12 | SPECIAL_FEATURES | ARRAY | YES | | MySQL SET split into an array: query with ARRAY_CONTAINS |
| 13 | VALID_FROM | TIMESTAMP_NTZ | NO | SCD2 | — |
| 14 | VALID_TO | TIMESTAMP_NTZ | NO | SCD2 | — |
| 15 | IS_CURRENT | BOOLEAN | NO | SCD2 | — |
| 16 | ROW_HASH | NUMBER(19,0) | NO | SCD2 | — |

The SCD2 columns here have no stored comment [Q2]. They work the same way as DIM_CUSTOMER's (same column names and types [Q2]).

## DIM_DATE

**Comment** [Q1]: grain: one row per calendar day, 2005-01-01 .. 2006-12-31 (730 days; covers every rental and payment)
**PK** date_key [Q3][DDL:55]. **Verified** unique: 730 / 730 [Q6]. The 730 count matches the comment [Q5]. The date range and
"covers every rental and payment" were not verified here.

| # | Column | Type [Q2] | Null? [Q2] | Key | Comment [Q2] |
|---:|---|---|---|---|---|
| 1 | DATE_KEY | NUMBER(38,0) | NO | PK | YYYYMMDD |
| 2 | FULL_DATE | DATE | NO | | — |
| 3 | YEAR | NUMBER(38,0) | NO | | — |
| 4 | QUARTER | NUMBER(38,0) | NO | | — |
| 5 | MONTH | NUMBER(38,0) | NO | | — |
| 6 | MONTH_NAME | TEXT(3) | NO | | — |
| 7 | YEAR_MONTH | TEXT(7) | NO | | e.g. 2005-07, for monthly charts |
| 8 | DAY_OF_WEEK | NUMBER(38,0) | NO | | ISO: 1 = Monday |
| 9 | DAY_NAME | TEXT(3) | NO | | — |
| 10 | IS_WEEKEND | BOOLEAN | NO | | — |

The fact references DIM_DATE twice, through payment_date_key and rental_date_key [Q7]. It is a role-playing dimension.

## DIM_STORE

**Comment** [Q1]: Type 1 — grain: one row per store
**PK** store_key [Q3][DDL:109]. **Verified** unique: 2 / 2 [Q6].

| # | Column | Type [Q2] | Null? [Q2] | Key | Comment [Q2] |
|---:|---|---|---|---|---|
| 1 | STORE_KEY | NUMBER(38,0) | NO | PK | = OLTP store.store_id (Type 1: overwritten on change) |
| 2 | STORE_NAME | TEXT(80) | NO | | — |
| 3 | ADDRESS | TEXT(50) | NO | | — |
| 4 | DISTRICT | TEXT(20) | NO | | — |
| 5 | CITY | TEXT(50) | NO | | — |
| 6 | COUNTRY | TEXT(50) | NO | | — |
| 7 | MANAGER_STAFF_ID | NUMBER(38,0) | NO | | — |
| 8 | MANAGER_NAME | TEXT(91) | NO | | — |

MANAGER_STAFF_ID is not a declared FK to DIM_STAFF [Q3].

## DIM_STAFF

**Comment** [Q1]: Type 1 — grain: one row per staff member
**PK** staff_key [Q3][DDL:118]. **Verified** unique: 2 / 2 [Q6].

| # | Column | Type [Q2] | Null? [Q2] | Key | Comment [Q2] |
|---:|---|---|---|---|---|
| 1 | STAFF_KEY | NUMBER(38,0) | NO | PK | = OLTP staff.staff_id (Type 1) |
| 2 | STAFF_NAME | TEXT(91) | NO | | — |
| 3 | EMAIL | TEXT(50) | YES | | — |
| 4 | STORE_ID | NUMBER(38,0) | NO | | the store the staff member works at |
| 5 | ACTIVE | BOOLEAN | NO | | — |

STORE_ID is not a declared FK to DIM_STORE [Q3].

---

## Queries

Each query was run exactly as written with `snow sql -c claude -q "<query>"`. Q2 also used `--format json` so that the
long comments would not be cut off.

**Q1. Tables, row counts, size, clustering, table comments**
```sql
SELECT table_name, table_type, row_count, bytes, clustering_key, comment
FROM SAKILA.INFORMATION_SCHEMA.TABLES
WHERE table_schema = 'DW' ORDER BY table_name;
```

**Q2. Columns: type, nullability, identity, column comments**
```sql
SELECT table_name, ordinal_position, column_name, data_type, character_maximum_length,
       numeric_precision, numeric_scale, is_nullable, is_identity, column_default, comment
FROM SAKILA.INFORMATION_SCHEMA.COLUMNS
WHERE table_schema = 'DW' ORDER BY table_name, ordinal_position;
```
`column_default` is NULL for every DW column. Identity columns: DIM_CUSTOMER.customer_sk and DIM_FILM.film_sk.

**Q3. Declared constraints and whether they are enforced**
```sql
SELECT table_name, constraint_type, constraint_name, enforced
FROM SAKILA.INFORMATION_SCHEMA.TABLE_CONSTRAINTS
WHERE table_schema = 'DW' ORDER BY table_name, constraint_type, constraint_name;
```
Result: 12 constraints in total, 1 PRIMARY KEY on each of the 6 tables and 6 FOREIGN KEYs on FACT_PAYMENT. All 12 have
`ENFORCED = NO`.

**Q4. Check on Q2: column counts per table**
```sql
SELECT table_name, COUNT(*) AS n_columns, COUNT_IF(is_nullable = 'YES') AS n_nullable,
       COUNT_IF(is_identity = 'YES') AS n_identity
FROM SAKILA.INFORMATION_SCHEMA.COLUMNS
WHERE table_schema = 'DW' GROUP BY table_name ORDER BY table_name;
```

**Q5. Check on Q1: real row counts and revenue (must be 67,406.56)**
```sql
SELECT 'DIM_CUSTOMER' AS t, COUNT(*) AS n, NULL AS revenue FROM SAKILA.DW.DIM_CUSTOMER
UNION ALL SELECT 'DIM_DATE',     COUNT(*), NULL        FROM SAKILA.DW.DIM_DATE
UNION ALL SELECT 'DIM_FILM',     COUNT(*), NULL        FROM SAKILA.DW.DIM_FILM
UNION ALL SELECT 'DIM_STAFF',    COUNT(*), NULL        FROM SAKILA.DW.DIM_STAFF
UNION ALL SELECT 'DIM_STORE',    COUNT(*), NULL        FROM SAKILA.DW.DIM_STORE
UNION ALL SELECT 'FACT_PAYMENT', COUNT(*), SUM(amount) FROM SAKILA.DW.FACT_PAYMENT
ORDER BY 1;
```

**Q6. Check on Q3: is each unenforced PK actually unique?**
```sql
SELECT 'DIM_CUSTOMER.customer_sk' AS pk, COUNT(*) AS n, COUNT(DISTINCT customer_sk) AS n_distinct FROM SAKILA.DW.DIM_CUSTOMER
UNION ALL SELECT 'DIM_DATE.date_key',       COUNT(*), COUNT(DISTINCT date_key)    FROM SAKILA.DW.DIM_DATE
UNION ALL SELECT 'DIM_FILM.film_sk',        COUNT(*), COUNT(DISTINCT film_sk)     FROM SAKILA.DW.DIM_FILM
UNION ALL SELECT 'DIM_STAFF.staff_key',     COUNT(*), COUNT(DISTINCT staff_key)   FROM SAKILA.DW.DIM_STAFF
UNION ALL SELECT 'DIM_STORE.store_key',     COUNT(*), COUNT(DISTINCT store_key)   FROM SAKILA.DW.DIM_STORE
UNION ALL SELECT 'FACT_PAYMENT.payment_id', COUNT(*), COUNT(DISTINCT payment_id)  FROM SAKILA.DW.FACT_PAYMENT
ORDER BY 1;
```

**Q7. Which table each foreign key points to**
```sql
SELECT fk.table_name AS fk_table, pk.table_name AS referenced_table, COUNT(*) AS n_fks,
       rc.match_option, rc.update_rule, rc.delete_rule
FROM SAKILA.INFORMATION_SCHEMA.REFERENTIAL_CONSTRAINTS rc
JOIN SAKILA.INFORMATION_SCHEMA.TABLE_CONSTRAINTS fk
  ON fk.constraint_name = rc.constraint_name AND fk.constraint_schema = rc.constraint_schema
JOIN SAKILA.INFORMATION_SCHEMA.TABLE_CONSTRAINTS pk
  ON pk.constraint_name = rc.unique_constraint_name AND pk.constraint_schema = rc.unique_constraint_schema
WHERE rc.constraint_schema = 'DW'
GROUP BY 1, 2, 4, 5, 6 ORDER BY 2;
```
Result: DIM_CUSTOMER 1, DIM_DATE 2, DIM_FILM 1, DIM_STAFF 1, DIM_STORE 1, for 6 FKs in total. This matches the 6 in Q3.

## Not covered by this dictionary
- **Referential integrity of the data.** The FKs are declared but not enforced. This document does not check for orphan keys in
  FACT_PAYMENT. `sql/sakila/part2_04_dw_checks.sql:15-18` checks orphans for customer_sk, film_sk, store_key and
  payment_date_key. It has no check for **staff_key** or **rental_date_key**.
- **Column-level FK mapping.** It comes from the DDL. Getting it from Snowflake would take `SHOW IMPORTED KEYS`, which is not a SELECT.
- **SAKILA.STAGING views** (CUSTOMER_SRC, FILM_SRC). They are out of scope because this dictionary covers DW tables only.
