#!/usr/bin/env bash
# Part 1 · Step 1 — export every Sakila table from Cloud SQL to headerless CSV, one file per table.
# Run in Cloud Shell after `source env.sh` (PROJECT, INSTANCE, BUCKET from the Week 2 kit). Idempotent: safe to re-run.
# Also exports three proof files: the source column types, the foreign keys and exact COUNT(*) per table.
set -euo pipefail
: "${PROJECT:?source env.sh first}" "${INSTANCE:?}" "${BUCKET:?}"
SRC_DB="sakila"
OUT="gs://$BUCKET/sakila"
gcloud config set project "$PROJECT" --quiet

# 1) the instance must exist and be running
if ! gcloud sql instances describe "$INSTANCE" --format='value(name)' >/dev/null 2>&1; then
  echo "instance $INSTANCE not found — check: gcloud sql instances list"; exit 1
fi
POLICY=$(gcloud sql instances describe "$INSTANCE" --format='value(settings.activationPolicy)')
if [ "$POLICY" = "NEVER" ]; then
  echo "instance $INSTANCE is stopped — starting it (1–2 min)…"
  gcloud sql instances patch "$INSTANCE" --activation-policy=ALWAYS --quiet
fi
gcloud sql instances describe "$INSTANCE" --format='table(name,databaseVersion,state,settings.activationPolicy)'

# 2) the bucket must exist, and the instance's service account must be allowed to WRITE to it
#    (Week 2 only granted objectViewer for the import; an export needs to create objects)
gcloud storage buckets describe "gs://$BUCKET" >/dev/null 2>&1 || gcloud storage buckets create "gs://$BUCKET" --uniform-bucket-level-access
SA=$(gcloud sql instances describe "$INSTANCE" --format='value(serviceAccountEmailAddress)')
gcloud storage buckets add-iam-policy-binding "gs://$BUCKET" --member="serviceAccount:$SA" --role=roles/storage.objectAdmin --quiet >/dev/null

# 3) one export per query. Escape = backslash (5C) so NULL is written as \N, matching the Snowflake file format.
export_csv() {  # $1 = file name, $2 = query
  echo "exporting $1…"
  gcloud sql export csv "$INSTANCE" "$OUT/$1.csv" --database="$SRC_DB" --query="$2" \
    --escape=5C --quote=22 --fields-terminated-by=2C --lines-terminated-by=0A --quiet
}

# 14 tables export as-is (SELECT * keeps the source column order, which COPY INTO relies on)
for t in actor category city country customer film film_actor film_category film_text inventory language payment rental store; do
  export_csv "$t" "SELECT * FROM $t"
done
# 2 tables hold binary columns that would corrupt a CSV, so they are converted to text on the way out:
#   address.location  GEOMETRY -> WKT text, e.g. POINT(-112.8 49.7)
#   staff.picture     BLOB     -> hex string (Snowflake BINARY reads hex by default)
export_csv address "SELECT address_id, address, address2, district, city_id, postal_code, phone, ST_AsText(location), last_update FROM address"
export_csv staff   "SELECT staff_id, first_name, last_name, address_id, HEX(picture), email, store_id, active, username, password, last_update FROM staff"

# 4) proof files: source schema, foreign keys, exact row counts (COUNT(*), not the estimate in information_schema.tables)
export_csv _columns "SELECT table_name, ordinal_position, column_name, column_type, is_nullable, column_key FROM information_schema.columns WHERE table_schema = '$SRC_DB' AND table_name IN (SELECT table_name FROM information_schema.tables WHERE table_schema = '$SRC_DB' AND table_type = 'BASE TABLE') ORDER BY table_name, ordinal_position"
export_csv _fks     "SELECT table_name, column_name, referenced_table_name, referenced_column_name, constraint_name FROM information_schema.key_column_usage WHERE table_schema = '$SRC_DB' AND referenced_table_name IS NOT NULL ORDER BY table_name, column_name"
COUNTS=""
for t in actor address category city country customer film film_actor film_category film_text inventory language payment rental staff store; do
  COUNTS="${COUNTS:+$COUNTS UNION ALL }SELECT '$t', COUNT(*) FROM $t"
done
export_csv _source_counts "$COUNTS"

# 5) bring the files into Cloud Shell and zip them for download
mkdir -p ~/sakila_csv
gcloud storage cp "$OUT/*.csv" ~/sakila_csv/
(cd ~ && rm -f sakila_csv.zip && zip -qr sakila_csv.zip sakila_csv)
ls -l ~/sakila_csv
echo "--- source row counts"; cat ~/sakila_csv/_source_counts.csv
echo "Checkpoint: 19 files (16 tables + _columns, _fks, _source_counts). Download ~/sakila_csv.zip next."
