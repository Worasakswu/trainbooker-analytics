-- grain: one row per scheduled departure (including departures nobody booked)
with seats as (
    select
        schedule_id,
        count(*) filter (where is_active)       as seats_sold,
        count(*) filter (where not is_active)   as seats_released
    from {{ ref('stg_tickets') }}
    group by schedule_id
),

bookings as (
    select
        schedule_id,
        count(*)                                as bookings,
        count(*) filter (where is_cancelled)    as cancelled_bookings,
        sum(paid_amount)                        as revenue
    from {{ ref('fact_bookings') }}
    group by schedule_id
)

select
    s.schedule_id,
    s.train_id,
    s.origin_station_id * 1000 + s.destination_station_id     as route_key,
    to_char(s.departure_date, 'YYYYMMDD')::int                as departure_date_key,
    s.departure_time,
    s.departure_hour,
    t.capacity,
    coalesce(seats.seats_sold, 0)                             as seats_sold,
    coalesce(seats.seats_released, 0)                         as seats_released,
    round(100.0 * coalesce(seats.seats_sold, 0) / t.capacity, 1) as occupancy_pct,
    coalesce(seats.seats_sold, 0) >= t.capacity               as is_sold_out,
    coalesce(b.bookings, 0)                                   as bookings,
    coalesce(b.cancelled_bookings, 0)                         as cancelled_bookings,
    coalesce(b.revenue, 0)                                    as revenue
from {{ ref('stg_schedules') }} s
join {{ ref('stg_trains') }} t using (train_id)
left join seats    using (schedule_id)
left join bookings b using (schedule_id)
