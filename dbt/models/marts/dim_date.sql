-- calendar dimension, one row per day
with days as (
    select d::date as date_day
    from generate_series(date '2025-01-01', date '2026-12-31', interval '1 day') as d
)

select
    to_char(date_day, 'YYYYMMDD')::int          as date_key,
    date_day,
    extract(year    from date_day)::int         as year,
    extract(quarter from date_day)::int         as quarter,
    extract(month   from date_day)::int         as month,
    to_char(date_day, 'Mon')                    as month_name,
    extract(day     from date_day)::int         as day_of_month,
    extract(isodow  from date_day)::int         as iso_day_of_week,   -- 1 = Monday
    to_char(date_day, 'Dy')                     as day_name,
    extract(isodow  from date_day) in (6, 7)    as is_weekend,
    case
        when extract(month from date_day) = 4
             and extract(day from date_day) between 10 and 17 then 'Songkran'
        when extract(month from date_day) = 1
             and extract(day from date_day) between 1 and 4   then 'New Year'
        when extract(month from date_day) = 12
             and extract(day from date_day) = 31              then 'New Year'
        else 'Normal'
    end                                         as holiday_period
from days
