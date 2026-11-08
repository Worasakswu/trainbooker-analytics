-- password_hash is deliberately NOT selected: it never leaves the OLTP database
select
    user_id,
    username,
    full_name,
    email,
    created_at as signed_up_at
from {{ source('oltp', 'users') }}
