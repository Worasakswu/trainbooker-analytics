-- grain: one row per booking
select
    b.booking_id,

    -- dimension keys
    b.user_id,
    s.schedule_id,
    s.train_id,
    s.origin_station_id * 1000 + s.destination_station_id      as route_key,
    s.origin_station_id,
    s.destination_station_id,
    to_char(b.booked_date,    'YYYYMMDD')::int                 as booked_date_key,
    to_char(s.departure_date, 'YYYYMMDD')::int                 as departure_date_key,

    -- descriptive
    b.booking_status,
    b.booked_at,
    s.departure_time,
    s.departure_hour,
    p.payment_method,
    coalesce(p.final_payment_status, 'none')                   as final_payment_status,

    -- measures
    seats.seats,
    s.ticket_price,
    s.ticket_price * seats.seats                               as gross_amount,
    coalesce(p.paid_amount, 0)                                 as paid_amount,
    coalesce(p.refunded_amount, 0)                             as refunded_amount,
    coalesce(p.failed_attempts, 0)                             as failed_payment_attempts,
    round(extract(epoch from s.departure_time - b.booked_at) / 3600.0, 2) as lead_time_hours,

    -- flags
    b.booking_status = 'confirmed'                             as is_confirmed,
    b.booking_status = 'cancelled'                             as is_cancelled
from {{ ref('stg_bookings') }} b
join {{ ref('stg_schedules') }} s using (schedule_id)
join {{ ref('int_booking_seats') }} seats using (booking_id)
left join {{ ref('int_booking_payments') }} p using (booking_id)
