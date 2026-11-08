select
    line_id,
    line_name
from {{ source('oltp', 'lines') }}
