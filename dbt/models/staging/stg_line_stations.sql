select
    line_id,
    station_id,
    station_order
from {{ source('oltp', 'line_stations') }}
