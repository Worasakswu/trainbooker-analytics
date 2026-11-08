select
    payment_id,
    booking_id,
    amount,
    payment_method,
    status as payment_status,
    paid_at
from {{ source('oltp', 'payments') }}
