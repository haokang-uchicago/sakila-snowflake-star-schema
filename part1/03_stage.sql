-- Part 1 · Step 3 — where the CSVs land in Snowflake: one file format that matches the Cloud SQL export, one internal stage.
-- Run All in Snowsight, then upload the 16 table CSVs into SAKILA.OLTP.SAKILA_STAGE (Snowsight: the stage → + Files).
-- Re-runnable: the format is replaced, the stage (and any files already uploaded to it) is kept.
USE ROLE SYSADMIN;
USE WAREHOUSE CLASS_WH;
USE SCHEMA SAKILA.OLTP;

-- How the export was written (gcloud sql export csv --escape=5C --quote=22):
--   no header row · comma separated · text in double quotes · NULL as \N · backslash is the escape character
--   timestamps as 2006-02-15 04:34:33 · staff.picture as a hex string
CREATE OR REPLACE FILE FORMAT sakila_csv
  TYPE = CSV
  FIELD_DELIMITER = ','
  SKIP_HEADER = 0
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  ESCAPE = '\\'
  ESCAPE_UNENCLOSED_FIELD = '\\'
  NULL_IF = ('\\N')
  EMPTY_FIELD_AS_NULL = FALSE                  -- "" stays an empty string: 599 address2 values are '' in the source, only 4 are NULL
  BINARY_FORMAT = HEX
  TIMESTAMP_FORMAT = 'YYYY-MM-DD HH24:MI:SS';

CREATE STAGE IF NOT EXISTS sakila_stage
  FILE_FORMAT = sakila_csv
  COMMENT = 'Sakila CSVs exported from Cloud SQL, one file per table';

-- checkpoint after the upload: 16 files (actor.csv … store.csv)
LIST @sakila_stage;
