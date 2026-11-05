-- One-off cleanup, run ONCE before re-running 02_create_oltp.sql with the kit's role (SYSADMIN) and warehouse (CLASS_WH).
-- The first run created SAKILA and COMPUTE_WH as ACCOUNTADMIN; the 16 tables were still empty, so nothing is lost.
USE ROLE ACCOUNTADMIN;
SELECT COUNT(*) AS rows_in_sakila_oltp FROM SAKILA.INFORMATION_SCHEMA.TABLES WHERE table_schema = 'OLTP' AND row_count > 0;  -- expect 0
DROP DATABASE IF EXISTS SAKILA;
DROP WAREHOUSE IF EXISTS COMPUTE_WH;
