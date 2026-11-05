# Part 4 — Sakila revenue dashboard (Streamlit in Snowflake, warehouse CLASS_WH with AUTO_SUSPEND = 60).
# Every number on the page comes from the star, SAKILA.DW. The "Check" expander recomputes each number from the
# normalized copy, SAKILA.OLTP, and shows MATCH / DIFF next to the SQL behind it.
# One filter — the payment date range — drives every query on the page, star and check alike.
import altair as alt
import pandas as pd
import streamlit as st

try:  # warehouse runtime
    from snowflake.snowpark.context import get_active_session
    session = get_active_session()
except Exception:  # container runtime (compute pool): the documented connection
    session = st.connection("snowflake").session()
DW, OLTP = "SAKILA.DW", "SAKILA.OLTP"


def q(sql: str) -> pd.DataFrame:
    df = session.sql(sql).to_pandas()
    df.columns = [c.lower() for c in df.columns]
    return df


def same(a, b) -> bool:
    if pd.isna(a) and pd.isna(b):  # e.g. revenue is NULL on both sides for a range with no payments
        return True
    return pd.notna(a) and pd.notna(b) and round(float(a), 2) == round(float(b), 2)


st.title("Sakila revenue")
st.caption("Reads the star schema SAKILA.DW · fact grain: one row per payment")

# ---------- the filter ----------
bounds = q(f"""SELECT MIN(d.full_date) AS lo, MAX(d.full_date) AS hi
FROM {DW}.FACT_PAYMENT f JOIN {DW}.DIM_DATE d ON d.date_key = f.payment_date_key""")
lo, hi = bounds.loc[0, "lo"], bounds.loc[0, "hi"]
picked = st.date_input("Payment date range", value=(lo, hi), min_value=lo, max_value=hi)
if not isinstance(picked, (list, tuple)) or len(picked) != 2:
    st.info("Pick an end date to finish the range.")
    st.stop()
start, end = picked  # datetime.date values from the widget, so safe to place in SQL

STAR = f"{DW}.FACT_PAYMENT f JOIN {DW}.DIM_DATE d ON d.date_key = f.payment_date_key"
STAR_WHERE = f"d.full_date BETWEEN '{start}' AND '{end}'"
OLTP_WHERE = f"p.payment_date::DATE BETWEEN '{start}' AND '{end}'"

# ---------- the SQL behind every number: star (shown) and normalized copy (check) ----------
SQL = {
    "kpis": (
        f"""SELECT SUM(f.amount) AS revenue, COUNT(*) AS payments, COUNT(DISTINCT c.customer_id) AS customers
FROM {STAR} JOIN {DW}.DIM_CUSTOMER c ON c.customer_sk = f.customer_sk
WHERE {STAR_WHERE}""",
        f"""SELECT SUM(p.amount) AS revenue, COUNT(*) AS payments, COUNT(DISTINCT p.customer_id) AS customers
FROM {OLTP}.PAYMENT p
WHERE {OLTP_WHERE}""",
    ),
    "month": (
        f"""SELECT d.year_month AS month, SUM(f.amount) AS revenue
FROM {STAR}
WHERE {STAR_WHERE}
GROUP BY 1 ORDER BY 1""",
        f"""SELECT TO_CHAR(p.payment_date, 'YYYY-MM') AS month, SUM(p.amount) AS revenue
FROM {OLTP}.PAYMENT p
WHERE {OLTP_WHERE}
GROUP BY 1 ORDER BY 1""",
    ),
    "category": (
        f"""SELECT fl.category, SUM(f.amount) AS revenue
FROM {STAR} JOIN {DW}.DIM_FILM fl ON fl.film_sk = f.film_sk
WHERE {STAR_WHERE}
GROUP BY 1 ORDER BY revenue DESC LIMIT 10""",
        f"""SELECT cat.name AS category, SUM(p.amount) AS revenue
FROM {OLTP}.PAYMENT p
JOIN {OLTP}.RENTAL r         ON r.rental_id     = p.rental_id
JOIN {OLTP}.INVENTORY i      ON i.inventory_id  = r.inventory_id
JOIN {OLTP}.FILM_CATEGORY fc ON fc.film_id      = i.film_id
JOIN {OLTP}.CATEGORY cat     ON cat.category_id = fc.category_id
WHERE {OLTP_WHERE}
GROUP BY 1""",
    ),
    "store": (
        f"""SELECT s.store_name AS store, SUM(f.amount) AS revenue, COUNT(*) AS payments
FROM {STAR} JOIN {DW}.DIM_STORE s ON s.store_key = f.store_key
WHERE {STAR_WHERE}
GROUP BY 1 ORDER BY 1""",
        f"""SELECT 'Store ' || i.store_id || ' (' || ci.city || ')' AS store, SUM(p.amount) AS revenue, COUNT(*) AS payments
FROM {OLTP}.PAYMENT p
JOIN {OLTP}.RENTAL r    ON r.rental_id    = p.rental_id
JOIN {OLTP}.INVENTORY i ON i.inventory_id = r.inventory_id
JOIN {OLTP}.STORE s     ON s.store_id     = i.store_id
JOIN {OLTP}.ADDRESS a   ON a.address_id   = s.address_id
JOIN {OLTP}.CITY ci     ON ci.city_id     = a.city_id
WHERE {OLTP_WHERE}
GROUP BY 1""",
    ),
}

kpi = q(SQL["kpis"][0])
month = q(SQL["month"][0])
category = q(SQL["category"][0])
store = q(SQL["store"][0])

# ---------- the page: three KPIs, revenue by month (line), top 10 categories (bar), revenue by store (table) ----------
c1, c2, c3 = st.columns(3)
c1.metric("Revenue", f"${float(kpi.loc[0, 'revenue'] or 0):,.2f}")
c2.metric("Payments", f"{int(kpi.loc[0, 'payments']):,}")
c3.metric("Paying customers", f"{int(kpi.loc[0, 'customers']):,}")

st.subheader("Revenue by month")
st.altair_chart(
    alt.Chart(month.assign(revenue=month["revenue"].astype(float))).mark_line(point=True).encode(
        x=alt.X("month:O", title="Month"),
        y=alt.Y("revenue:Q", title="Revenue ($)", scale=alt.Scale(zero=True)),
        tooltip=["month", alt.Tooltip("revenue:Q", format=",.2f")]),
    use_container_width=True)

st.subheader("Top 10 film categories by revenue")
st.altair_chart(
    alt.Chart(category.assign(revenue=category["revenue"].astype(float))).mark_bar().encode(
        x=alt.X("revenue:Q", title="Revenue ($)"),
        y=alt.Y("category:N", sort="-x", title=None),
        tooltip=["category", alt.Tooltip("revenue:Q", format=",.2f")]),
    use_container_width=True)

st.subheader("Revenue by store")
st.dataframe(store.assign(revenue=store["revenue"].astype(float)).set_index("store"))


# ---------- Check: every number above, recomputed from SAKILA.OLTP ----------
def compare(star_df, oltp_df, key, cols):
    m = star_df.merge(oltp_df, on=key, how="left", suffixes=("_star", "_oltp"))
    ok = pd.Series(True, index=m.index)
    for c in cols:
        ok &= pd.Series([same(a, b) for a, b in zip(m[f"{c}_star"], m[f"{c}_oltp"])], index=m.index)
    m["result"] = ["MATCH" if v else "DIFF" for v in ok]
    return m


checks = [
    ("Three KPIs", compare(kpi.assign(k=1), q(SQL["kpis"][1]).assign(k=1), "k", ["revenue", "payments", "customers"]).drop(columns="k"), SQL["kpis"]),
    ("Revenue by month", compare(month, q(SQL["month"][1]), "month", ["revenue"]), SQL["month"]),
    ("Top 10 film categories", compare(category, q(SQL["category"][1]), "category", ["revenue"]), SQL["category"]),
    ("Revenue by store", compare(store, q(SQL["store"][1]), "store", ["revenue", "payments"]), SQL["store"]),
]
n_rows = sum(len(t) for _, t, _ in checks)
n_diff = sum(int((t["result"] == "DIFF").sum()) for _, t, _ in checks)

with st.expander(f"Check — {n_rows - n_diff} of {n_rows} rows MATCH the normalized copy (SAKILA.OLTP)"):
    (st.success if n_diff == 0 else st.error)(
        f"Date range {start} to {end}: {n_rows - n_diff} MATCH, {n_diff} DIFF.")
    for title, table, (star_sql, oltp_sql) in checks:
        st.markdown(f"**{title}**")
        st.dataframe(table)
        st.caption("Shown on the page (star, SAKILA.DW):")
        st.code(star_sql, language="sql")
        st.caption("Recomputed from the normalized copy (SAKILA.OLTP):")
        st.code(oltp_sql, language="sql")
