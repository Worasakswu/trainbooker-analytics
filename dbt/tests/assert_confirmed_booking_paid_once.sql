-- every confirmed booking has exactly one successful payment
select b.booking_id
from {{ ref('stg_bookings') }} b
left join {{ ref('stg_payments') }} p
  on p.booking_id = b.booking_id and p.payment_status = 'paid'
where b.booking_status = 'confirmed'
group by b.booking_id
having count(p.payment_id) <> 1
