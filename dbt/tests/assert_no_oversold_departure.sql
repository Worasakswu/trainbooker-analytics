select schedule_id, seats_sold, capacity
from {{ ref('fact_schedule_occupancy') }}
where seats_sold > capacity
