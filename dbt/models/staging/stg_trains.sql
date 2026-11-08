select
    train_id,
    train_name,
    train_type,
    total_seats as capacity
from {{ source('oltp', 'trains') }}
