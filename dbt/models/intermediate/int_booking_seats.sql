-- number of seats (tickets) on each booking
select
    booking_id,
    count(*)                                as seats,
    count(*) filter (where is_active)       as active_seats
from {{ ref('stg_tickets') }}
group by booking_id
