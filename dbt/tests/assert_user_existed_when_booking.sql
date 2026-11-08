-- a user can't book before signing up
select f.booking_id, f.booked_at, u.signed_up_at
from {{ ref('fact_bookings') }} f
join {{ ref('dim_user') }} u using (user_id)
where f.booked_at < u.signed_up_at
