-- pending / cancelled bookings never keep a successful payment,
-- and refunds only happen on cancelled bookings
select booking_id, booking_status, paid_amount, refunded_amount
from {{ ref('fact_bookings') }}
where (booking_status <> 'confirmed' and paid_amount > 0)
   or (booking_status <> 'cancelled' and refunded_amount > 0)
