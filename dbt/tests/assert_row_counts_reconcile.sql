-- every booking, departure and sold seat reaches the marts exactly once
with counts as (
    select 'bookings' as entity,
           (select count(*) from {{ source('oltp', 'bookings') }}) as source_rows,
           (select count(*) from {{ ref('fact_bookings') }})       as mart_rows
    union all
    select 'schedules',
           (select count(*) from {{ source('oltp', 'schedules') }}),
           (select count(*) from {{ ref('fact_schedule_occupancy') }})
    union all
    select 'seats_sold',
           (select count(*) from {{ source('oltp', 'tickets') }} where is_active),
           (select coalesce(sum(seats_sold), 0) from {{ ref('mart_daily_route_kpis') }})
)
select * from counts
where source_rows <> mart_rows
