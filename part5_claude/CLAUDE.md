# CLAUDE.md — ADSP 31011 Assignment 4: an agent with a warehouse (Snowflake, Sakila)

## What this folder is
Sakila moved from Cloud SQL for MySQL into Snowflake. SAKILA.OLTP is the normalized copy (16 tables), SAKILA.DW is the star built
from it, SAKILA.STAGING holds two views that feed the DW loads. You (Claude Code) run in a terminal and talk to Snowflake ONLY through
the Snowflake CLI connection named `claude`: user CLAUDE_AGENT, role CLAUDE_RO (SELECT only), warehouse CLASS_WH.

## Facts you must not guess
- Read the files in sql/sakila/ before writing any query; never invent a column. They are copies of the student's code:
  part1_02_create_oltp.sql (OLTP DDL) · part2_01_dw_ddl.sql (DW + STAGING DDL) · part2_02_load_dims.sql (dimension MERGEs) ·
  part2_03_load_fact.sql (fact MERGE) · part2_04_dw_checks.sql (star vs OLTP checks) · streamlit_app.py (the Part 4 app).
  Snowflake upper-cases unquoted names — write them unquoted.
- OLTP: 16 tables, 47,268 rows; payment 16,044 · rental 16,044 · customer 599 · film 1,000. Revenue SUM(payment.amount) = 67,406.56.
- DW grain: FACT_PAYMENT has one row per payment (payment_id), 16,044 rows, SUM(amount) = 67,406.56.
  Keys: payment_date_key / rental_date_key → DIM_DATE; customer_sk → DIM_CUSTOMER (version valid at payment time);
  film_sk → DIM_FILM (version valid at rental time); store_key = the store that owns the rented copy (inventory.store_id); staff_key.
- DIM_CUSTOMER and DIM_FILM are SCD Type 2 (valid_from inclusive, valid_to exclusive, is_current, row_hash). Join the fact to them on
  customer_sk / film_sk, never on the natural key (that multiplies rows for any entity with more than one version).
- Known state: customer 1 (MARY SMITH) was moved on purpose in OLTP from Sasebo, Japan to Joliet, United States (address_id 5 was
  updated). DIM_CUSTOMER has 600 rows, 599 current.
- Expected checks: revenue by month 2005-05 4,823.44 · 2005-06 9,629.89 · 2005-07 28,368.91 · 2005-08 24,070.14 · 2006-02 514.18;
  by store: Store 1 (Lethbridge) 33,679.79 · Store 2 (Woodridge) 33,726.77; top category Sports 5,314.21.
- Snowflake does not enforce PRIMARY/FOREIGN KEY — a duplicate loads silently, so every result needs a reconciliation.
- Cortex AI is NOT available on this trial account. Do not suggest AI_COMPLETE or other Cortex functions.

## How to work here
- Run SQL only as: snow sql -c claude -q "<one SELECT>". Never use another connection, never `snow connection`, never read ~/.snowflake.
- Every query comes with a check query that must reconcile (a COUNT at the grain, a SUM that must equal 67,406.56).
- Read-only. You cannot write in Snowflake (CLAUDE_RO has SELECT only) and the deny list blocks DROP/DELETE/UPDATE/ALTER/MERGE/GRANT.
  If asked to change data, say so and give the SQL as text for the student to run as themselves.
- Use the grain-reviewer subagent for any DDL review; use /dw-reconcile for any "is the warehouse right?" question.
- Append each request and your answer, one line each, to prompts.md; the student records what was wrong and what they changed.
- Never write account identifiers, keys, tokens or project ids into any file.
