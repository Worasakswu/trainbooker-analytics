"""
TrainBooker dashboard — reads the dbt marts (schema `marts`).

Run (after `dbt build`):
    pip install -r dashboard/requirements.txt
    streamlit run dashboard/app.py
"""

from __future__ import annotations

import os
from contextlib import closing
from datetime import date
from decimal import Decimal

import altair as alt
import pandas as pd
import psycopg2
import streamlit as st

st.set_page_config(page_title="TrainBooker Analytics", page_icon="🚆", layout="wide")

# ---------------------------------------------------------------------------
# Colors: categorical slots 1-2, validated for color-blind separation and
# contrast. Each theme gets its own steps. A direction keeps its color
# whatever the filters.
# ---------------------------------------------------------------------------
def _is_dark() -> bool:
    try:
        return st.context.theme.type == "dark"
    except Exception:          # older Streamlit: no theme info -> light steps
        return False


BLUE, ORANGE = ("#3987e5", "#d95926") if _is_dark() else ("#2a78d6", "#eb6834")
DIRECTION_SCALE = alt.Scale(domain=["outbound", "inbound"], range=[BLUE, ORANGE])


# ---------------------------------------------------------------------------
# Data access
# ---------------------------------------------------------------------------
def _connect():
    return psycopg2.connect(
        host=os.getenv("TB_PG_HOST", "localhost"),
        port=int(os.getenv("TB_PG_PORT", "5544")),
        user=os.getenv("TB_PG_USER", "trainbooker"),
        password=os.getenv("TB_PG_PASSWORD", "trainbooker"),
        dbname=os.getenv("TB_PG_DB", "trainbooker"),
    )


@st.cache_data(ttl=600, show_spinner=False)
def query(sql: str, params: dict | None = None) -> pd.DataFrame:
    with closing(_connect()) as conn, conn.cursor() as cur:
        cur.execute(sql, params or {})
        cols = [c.name for c in cur.description]
        df = pd.DataFrame(cur.fetchall(), columns=cols)
    # Postgres numeric -> Decimal; charts need plain floats
    for c in df.columns:
        if df[c].map(lambda v: isinstance(v, Decimal)).any():
            df[c] = df[c].astype(float)
    return df


def chart(c: alt.Chart, height: int = 280):
    st.altair_chart(c.properties(height=height), width="stretch")


# ---------------------------------------------------------------------------
# Header + filters (one row, above every chart)
# ---------------------------------------------------------------------------
st.title("🚆 TrainBooker Analytics")
st.caption("Bookings on Thai rail routes, Jan–Jun 2026 · source: dbt marts "
           "(`mart_daily_route_kpis`, `fact_schedule_occupancy`, `fact_bookings`)")

try:
    bounds = query("select min(travel_date) as lo, max(travel_date) as hi from marts.mart_daily_route_kpis")
except psycopg2.OperationalError as e:
    st.error(f"Can't connect to Postgres. Is `docker compose up -d` running? \n\n{e}")
    st.stop()
except psycopg2.errors.UndefinedTable:
    st.error("The `marts` tables don't exist yet. Run `cd dbt && dbt build --profiles-dir .` first.")
    st.stop()

lo, hi = bounds.loc[0, "lo"], bounds.loc[0, "hi"]
lines = query("select distinct line_name from marts.dim_route order by 1")["line_name"].tolist()

f1, f2, f3 = st.columns([2, 2, 2])
with f1:
    picked = st.date_input("Travel dates", value=(lo, hi), min_value=lo, max_value=hi)
with f2:
    directions = st.multiselect("Direction", ["outbound", "inbound"], default=["outbound", "inbound"],
                                help="outbound = leaving Krung Thep Aphiwat, inbound = arriving there")
with f3:
    picked_lines = st.multiselect("Line", lines, default=lines)

# date_input returns a single date while the user is still picking the range
if isinstance(picked, (tuple, list)) and len(picked) == 2:
    start, end = picked
else:
    start = end = picked if isinstance(picked, date) else lo

if not directions or not picked_lines:
    st.info("Pick at least one direction and one line.")
    st.stop()

P = {"start": start, "end": end, "dirs": list(directions), "lines": list(picked_lines)}
ROUTE_FILTER = "r.direction = any(%(dirs)s) and r.line_name = any(%(lines)s)"

# ---------------------------------------------------------------------------
# KPI tiles
# ---------------------------------------------------------------------------
kpi = query(f"""
    select coalesce(sum(k.revenue), 0)                                         as revenue,
           coalesce(sum(k.seats_sold), 0)                                      as seats,
           round(100.0 * sum(k.seats_sold) / nullif(sum(k.capacity_seats), 0), 1) as occupancy,
           round(100.0 * sum(k.cancelled_bookings) / nullif(sum(k.bookings), 0), 1) as cancel_rate,
           coalesce(sum(k.sold_out_departures), 0)                             as sold_out
    from marts.mart_daily_route_kpis k
    join marts.dim_route r using (route_key)
    where k.travel_date between %(start)s and %(end)s and {ROUTE_FILTER}
""", P).iloc[0]

m1, m2, m3, m4, m5 = st.columns(5)
m1.metric("Revenue (paid)", f"฿{float(kpi.revenue):,.0f}")
m2.metric("Seats sold", f"{int(kpi.seats):,}")
m3.metric("Avg occupancy", f"{float(kpi.occupancy or 0):.1f}%")
m4.metric("Cancellation rate", f"{float(kpi.cancel_rate or 0):.1f}%")
m5.metric("Sold-out departures", f"{int(kpi.sold_out):,}")

st.divider()

# ---------------------------------------------------------------------------
# 1. Seats sold per day, by direction  (shows the Songkran rush)
# ---------------------------------------------------------------------------
st.subheader("Seats sold per day")
st.caption("Outbound spikes on 10–12 April as people leave Bangkok for Songkran; "
           "the return rush follows on 15–17 April.")

daily = query(f"""
    select k.travel_date, r.direction, sum(k.seats_sold) as seats_sold, sum(k.revenue) as revenue
    from marts.mart_daily_route_kpis k
    join marts.dim_route r using (route_key)
    where k.travel_date between %(start)s and %(end)s and {ROUTE_FILTER}
    group by 1, 2 order by 1
""", P)
daily["travel_date"] = pd.to_datetime(daily["travel_date"])
daily["seats_sold"] = daily["seats_sold"].astype(int)

base = alt.Chart(daily).encode(
    x=alt.X("travel_date:T", title=None, axis=alt.Axis(format="%d %b", grid=False)),
    y=alt.Y("seats_sold:Q", title="Seats sold"),
    color=alt.Color("direction:N", scale=DIRECTION_SCALE, title="Direction",
                    legend=alt.Legend(orient="top")),
)
hover = alt.selection_point(fields=["travel_date"], nearest=True, on="mouseover", empty=False)
lines_ = base.mark_line(strokeWidth=2)
points = base.mark_point(size=60, filled=True).encode(
    opacity=alt.condition(hover, alt.value(1), alt.value(0)),
    tooltip=[alt.Tooltip("travel_date:T", title="Date", format="%a %d %b %Y"),
             alt.Tooltip("direction:N", title="Direction"),
             alt.Tooltip("seats_sold:Q", title="Seats sold", format=","),
             alt.Tooltip("revenue:Q", title="Revenue (฿)", format=",.0f")],
).add_params(hover)
rule = alt.Chart(daily).mark_rule(color="gray", strokeWidth=1).encode(
    x="travel_date:T").transform_filter(hover)
chart(alt.layer(lines_, points, rule), height=320)

# ---------------------------------------------------------------------------
# 2 + 3. Departure hour and weekday
# ---------------------------------------------------------------------------
left, right = st.columns(2)

with left:
    st.subheader("Occupancy by departure hour")
    by_hour = query(f"""
        select o.departure_hour,
               round(100.0 * sum(o.seats_sold) / sum(o.capacity), 1) as occupancy_pct,
               count(*)                                              as departures,
               sum(o.seats_sold)                                     as seats_sold
        from marts.fact_schedule_occupancy o
        join marts.dim_route r using (route_key)
        join marts.dim_date  d on d.date_key = o.departure_date_key
        where d.date_day between %(start)s and %(end)s and {ROUTE_FILTER}
        group by 1 order by 1
    """, P)
    by_hour["label"] = by_hour["departure_hour"].map(lambda h: f"{int(h):02d}:00")
    by_hour["occupancy_pct"] = by_hour["occupancy_pct"].astype(float)
    chart(alt.Chart(by_hour).mark_bar(color=BLUE, cornerRadiusEnd=4, size=22).encode(
        x=alt.X("label:N", title="Departure hour", sort=None, axis=alt.Axis(labelAngle=0)),
        y=alt.Y("occupancy_pct:Q", title="Occupancy %"),
        tooltip=[alt.Tooltip("label:N", title="Hour"),
                 alt.Tooltip("occupancy_pct:Q", title="Occupancy %", format=".1f"),
                 alt.Tooltip("departures:Q", title="Departures", format=","),
                 alt.Tooltip("seats_sold:Q", title="Seats sold", format=",")],
    ))

with right:
    st.subheader("Average seats sold per day, by weekday")
    by_dow = query(f"""
        select d.iso_day_of_week, d.day_name,
               round(sum(k.seats_sold)::numeric / count(distinct k.travel_date), 0) as avg_seats
        from marts.mart_daily_route_kpis k
        join marts.dim_route r using (route_key)
        join marts.dim_date  d on d.date_day = k.travel_date
        where k.travel_date between %(start)s and %(end)s and {ROUTE_FILTER}
        group by 1, 2 order by 1
    """, P)
    by_dow["avg_seats"] = by_dow["avg_seats"].astype(float)
    chart(alt.Chart(by_dow).mark_bar(color=BLUE, cornerRadiusEnd=4, size=26).encode(
        x=alt.X("day_name:N", title=None, sort=by_dow["day_name"].tolist(), axis=alt.Axis(labelAngle=0)),
        y=alt.Y("avg_seats:Q", title="Avg seats sold / day"),
        tooltip=[alt.Tooltip("day_name:N", title="Day"),
                 alt.Tooltip("avg_seats:Q", title="Avg seats / day", format=",.0f")],
    ))

# ---------------------------------------------------------------------------
# 4 + 5. Cancellations by lead time, revenue by customer segment
# ---------------------------------------------------------------------------
left, right = st.columns(2)

with left:
    st.subheader("Cancellation rate by how early people book")
    lead = query(f"""
        select case
                 when f.lead_time_hours < 12      then '1. < 12 hours'
                 when f.lead_time_hours < 24 * 7  then '2. 12h – 7 days'
                 when f.lead_time_hours < 24 * 30 then '3. 7 – 30 days'
                 else                                  '4. 30+ days'
               end                                                   as bucket,
               count(*)                                              as bookings,
               round(100.0 * avg(f.is_cancelled::int), 1)            as cancel_rate
        from marts.fact_bookings f
        join marts.dim_route r using (route_key)
        join marts.dim_date  d on d.date_key = f.departure_date_key
        where d.date_day between %(start)s and %(end)s and {ROUTE_FILTER}
        group by 1 order by 1
    """, P)
    lead["lead_time"] = lead["bucket"].str[3:]
    lead["cancel_rate"] = lead["cancel_rate"].astype(float)
    chart(alt.Chart(lead).mark_bar(color=BLUE, cornerRadiusEnd=4, size=40).encode(
        x=alt.X("lead_time:N", title="Booked ahead of departure", sort=lead["lead_time"].tolist(),
                axis=alt.Axis(labelAngle=0)),
        y=alt.Y("cancel_rate:Q", title="Cancelled %"),
        tooltip=[alt.Tooltip("lead_time:N", title="Booked"),
                 alt.Tooltip("cancel_rate:Q", title="Cancelled %", format=".1f"),
                 alt.Tooltip("bookings:Q", title="Bookings", format=",")],
    ))

with right:
    st.subheader("Revenue by customer segment")
    seg = query(f"""
        select u.customer_segment                as segment,
               count(distinct f.user_id)         as users,
               sum(f.paid_amount)                as revenue
        from marts.fact_bookings f
        join marts.dim_user  u using (user_id)
        join marts.dim_route r using (route_key)
        join marts.dim_date  d on d.date_key = f.departure_date_key
        where d.date_day between %(start)s and %(end)s and {ROUTE_FILTER}
          and f.paid_amount > 0
        group by 1
    """, P)
    order = ["frequent", "regular", "occasional"]
    seg = seg.set_index("segment").reindex(order).dropna().reset_index()
    seg["revenue"] = seg["revenue"].astype(float)
    total = seg["revenue"].sum() or 1
    seg["share"] = (100 * seg["revenue"] / total).round(1)
    seg["users_share"] = (100 * seg["users"] / seg["users"].sum()).round(1)
    chart(alt.Chart(seg).mark_bar(color=BLUE, cornerRadiusEnd=4, size=26).encode(
        y=alt.Y("segment:N", title=None, sort=order),
        x=alt.X("revenue:Q", title="Revenue (฿)", axis=alt.Axis(format="~s")),
        tooltip=[alt.Tooltip("segment:N", title="Segment"),
                 alt.Tooltip("revenue:Q", title="Revenue (฿)", format=",.0f"),
                 alt.Tooltip("share:Q", title="% of revenue", format=".1f"),
                 alt.Tooltip("users:Q", title="Users", format=","),
                 alt.Tooltip("users_share:Q", title="% of users", format=".1f")],
    ), height=200)
    st.caption("Segments use each user's all-time confirmed trips: "
               "frequent ≥ 20, regular 5–19, occasional 1–4.")

# ---------------------------------------------------------------------------
# Busiest departures + table view of the daily data
# ---------------------------------------------------------------------------
st.subheader("Busiest departures")
top = query(f"""
    select o.departure_time, t.train_name, t.train_type, r.route_name,
           o.seats_sold, o.capacity, o.occupancy_pct, o.is_sold_out
    from marts.fact_schedule_occupancy o
    join marts.dim_train t using (train_id)
    join marts.dim_route r using (route_key)
    join marts.dim_date  d on d.date_key = o.departure_date_key
    where d.date_day between %(start)s and %(end)s and {ROUTE_FILTER}
    order by o.occupancy_pct desc, o.departure_time
    limit 10
""", P)
top["departure_time"] = pd.to_datetime(top["departure_time"]).dt.tz_convert("Asia/Bangkok").dt.strftime("%a %d %b %Y %H:%M")
top["is_sold_out"] = top["is_sold_out"].map({True: "✅ sold out", False: ""})
top["occupancy_pct"] = top["occupancy_pct"].astype(float)
st.dataframe(
    top.rename(columns={"departure_time": "Departure", "train_name": "Train", "train_type": "Type",
                        "route_name": "Route", "seats_sold": "Seats sold", "capacity": "Capacity",
                        "occupancy_pct": "Occupancy %", "is_sold_out": ""}),
    hide_index=True, width="stretch",
)

with st.expander("Show daily data as a table"):
    st.dataframe(daily.assign(travel_date=daily["travel_date"].dt.date),
                 hide_index=True, width="stretch")
