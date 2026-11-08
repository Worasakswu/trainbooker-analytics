-- the marts must not gain or lose money on the way from the OLTP tables
with source_total as (
    select coalesce(sum(amount), 0) as amount
    from {{ source('oltp', 'payments') }}
    where status = 'paid'
),
fact_total as (
    select coalesce(sum(paid_amount), 0) as amount from {{ ref('fact_bookings') }}
),
occupancy_total as (
    select coalesce(sum(revenue), 0) as amount from {{ ref('fact_schedule_occupancy') }}
),
kpi_total as (
    select coalesce(sum(revenue), 0) as amount from {{ ref('mart_daily_route_kpis') }}
)
select s.amount as source, f.amount as fact_bookings, o.amount as occupancy, k.amount as daily_kpis
from source_total s, fact_total f, occupancy_total o, kpi_total k
where s.amount <> f.amount or s.amount <> o.amount or s.amount <> k.amount
