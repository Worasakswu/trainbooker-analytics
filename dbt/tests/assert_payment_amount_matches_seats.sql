-- any paid or refunded amount equals ticket price x seats
select booking_id, gross_amount, paid_amount, refunded_amount
from {{ ref('fact_bookings') }}
where (paid_amount     > 0 and paid_amount     <> gross_amount)
   or (refunded_amount > 0 and refunded_amount <> gross_amount)
