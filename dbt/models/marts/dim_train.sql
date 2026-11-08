select
    train_id,
    train_name,
    train_type,
    capacity
from {{ ref('stg_trains') }}
