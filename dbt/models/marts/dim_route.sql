-- one row per origin -> destination pair that has a schedule
with pairs as (
    select distinct origin_station_id, destination_station_id
    from {{ ref('stg_schedules') }}
),

-- the line both stations are on (the interchange is on every line)
route_line as (
    select
        p.origin_station_id,
        p.destination_station_id,
        min(l.line_name) as line_name
    from pairs p
    join {{ ref('stg_line_stations') }} o
      on o.station_id = p.origin_station_id
    join {{ ref('stg_line_stations') }} d
      on d.station_id = p.destination_station_id
     and d.line_id = o.line_id
    join {{ ref('stg_lines') }} l
      on l.line_id = o.line_id
    group by 1, 2
),

hub as (   -- the interchange station is treated as "Bangkok"
    select station_id
    from {{ ref('dim_station') }}
    where is_interchange
)

select
    p.origin_station_id * 1000 + p.destination_station_id   as route_key,
    p.origin_station_id,
    p.destination_station_id,
    o.station_name || ' → ' || d.station_name               as route_name,
    rl.line_name,
    case
        when p.origin_station_id      in (select station_id from hub) then 'outbound'
        when p.destination_station_id in (select station_id from hub) then 'inbound'
        else 'other'
    end                                                     as direction
from pairs p
join {{ ref('stg_stations') }} o on o.station_id = p.origin_station_id
join {{ ref('stg_stations') }} d on d.station_id = p.destination_station_id
left join route_line rl
  on rl.origin_station_id = p.origin_station_id
 and rl.destination_station_id = p.destination_station_id
