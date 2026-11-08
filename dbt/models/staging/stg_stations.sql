select
    station_id,
    station_name,
    province
from {{ source('oltp', 'stations') }}
