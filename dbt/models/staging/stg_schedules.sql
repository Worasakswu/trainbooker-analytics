select
    schedule_id,
    train_id,
    origin_station_id,
    destination_station_id,
    departure_time,
    arrival_time,
    (departure_time at time zone 'Asia/Bangkok')::date             as departure_date,
    extract(hour from departure_time at time zone 'Asia/Bangkok')::int as departure_hour,
    extract(epoch from arrival_time - departure_time)::int / 60    as duration_minutes,
    price as ticket_price
from {{ source('oltp', 'schedules') }}
