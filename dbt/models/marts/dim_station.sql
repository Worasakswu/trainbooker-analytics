with station_lines as (
    select
        ls.station_id,
        string_agg(l.line_name, ', ' order by l.line_id) as line_names,
        count(*)                                          as n_lines
    from {{ ref('stg_line_stations') }} ls
    join {{ ref('stg_lines') }} l using (line_id)
    group by ls.station_id
)

select
    s.station_id,
    s.station_name,
    s.province,
    sl.line_names,
    coalesce(sl.n_lines, 0) > 1 as is_interchange
from {{ ref('stg_stations') }} s
left join station_lines sl using (station_id)
