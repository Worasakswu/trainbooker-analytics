select
    ticket_id,
    booking_id,
    schedule_id,
    seat_number,
    is_active
from {{ source('oltp', 'tickets') }}
