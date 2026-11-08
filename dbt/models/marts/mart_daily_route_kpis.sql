-- one row per travel day and route: the table the dashboard reads
select
    d.date_day                                                  as travel_date,
    d.day_name,
    d.is_weekend,
    d.holiday_period,
    r.route_key,
    r.route_name,
    r.line_name,
    r.direction,
    count(*)                                                    as departures,
    sum(o.capacity)                                             as capacity_seats,
    sum(o.seats_sold)                                           as seats_sold,
    round(100.0 * sum(o.seats_sold) / sum(o.capacity), 1)       as occupancy_pct,
    count(*) filter (where o.is_sold_out)                       as sold_out_departures,
    sum(o.bookings)                                             as bookings,
    sum(o.cancelled_bookings)                                   as cancelled_bookings,
    round(100.0 * sum(o.cancelled_bookings) / nullif(sum(o.bookings), 0), 1) as cancellation_rate_pct,
    sum(o.revenue)                                              as revenue
from {{ ref('fact_schedule_occupancy') }} o
join {{ ref('dim_date') }}  d on d.date_key  = o.departure_date_key
join {{ ref('dim_route') }} r on r.route_key = o.route_key
group by 1, 2, 3, 4, 5, 6, 7, 8
