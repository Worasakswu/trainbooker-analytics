select
    booking_id,
    user_id,
    schedule_id,
    status as booking_status,
    booked_at,
    (booked_at at time zone 'Asia/Bangkok')::date as booked_date
from {{ source('oltp', 'bookings') }}
