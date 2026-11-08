-- a booking must be made before the train leaves
select booking_id, booked_at, departure_time
from {{ ref('fact_bookings') }}
where booked_at >= departure_time
