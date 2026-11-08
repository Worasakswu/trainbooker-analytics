with booking_stats as (
    select
        b.user_id,
        min(b.booked_at)                                             as first_booking_at,
        max(b.booked_at)                                             as last_booking_at,
        count(*)                                                     as total_bookings,
        count(*) filter (where b.booking_status = 'confirmed')       as confirmed_bookings,
        coalesce(sum(p.paid_amount), 0)                              as lifetime_revenue
    from {{ ref('stg_bookings') }} b
    left join {{ ref('int_booking_payments') }} p using (booking_id)
    group by b.user_id
)

select
    u.user_id,
    u.username,
    u.full_name,
    u.signed_up_at,
    to_char(u.signed_up_at at time zone 'Asia/Bangkok', 'YYYYMMDD')::int as signup_date_key,
    s.first_booking_at,
    s.last_booking_at,
    coalesce(s.total_bookings, 0)      as total_bookings,
    coalesce(s.confirmed_bookings, 0)  as confirmed_bookings,
    coalesce(s.lifetime_revenue, 0)    as lifetime_revenue,
    case
        when coalesce(s.confirmed_bookings, 0) >= 20 then 'frequent'
        when coalesce(s.confirmed_bookings, 0) >= 5  then 'regular'
        when coalesce(s.confirmed_bookings, 0) >= 1  then 'occasional'
        else 'no_trips'
    end                                as customer_segment
from {{ ref('stg_users') }} u
left join booking_stats s using (user_id)
