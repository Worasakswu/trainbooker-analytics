-- =====================================================================
-- TrainBooker — example queries
-- Run:  docker compose exec -T db psql -U trainbooker -d trainbooker < sql/queries/example_queries.sql
-- =====================================================================

-- Q1. Timetable with origin / destination provinces
SELECT
    s.schedule_id,
    t.train_name,
    so.station_name  AS origin_station,
    so.province      AS origin_province,
    sd.station_name  AS destination_station,
    sd.province      AS destination_province,
    s.departure_time,
    s.arrival_time,
    s.price
FROM schedules s
JOIN trains   t  ON t.train_id   = s.train_id
JOIN stations so ON so.station_id = s.origin_station_id
JOIN stations sd ON sd.station_id = s.destination_station_id
ORDER BY s.departure_time;


-- Q2. Booking report per user
SELECT
    b.booking_id,
    u.full_name,
    u.email,
    t.train_name,
    so.station_name AS origin_station,
    sd.station_name AS destination_station,
    s.departure_time,
    b.status,
    b.booked_at
FROM bookings b
JOIN users     u  ON u.user_id     = b.user_id
JOIN schedules s  ON s.schedule_id = b.schedule_id
JOIN trains    t  ON t.train_id    = s.train_id
JOIN stations  so ON so.station_id = s.origin_station_id
JOIN stations  sd ON sd.station_id = s.destination_station_id
ORDER BY b.booking_id;


-- Q3. Longest trip
SELECT
    t.train_name,
    so.station_name AS origin_station,
    sd.station_name AS destination_station,
    s.arrival_time - s.departure_time AS travel_duration
FROM schedules s
JOIN trains   t  ON t.train_id    = s.train_id
JOIN stations so ON so.station_id = s.origin_station_id
JOIN stations sd ON sd.station_id = s.destination_station_id
ORDER BY travel_duration DESC
LIMIT 1;


-- Q4. Seats left on every schedule (capacity minus active tickets)
SELECT
    s.schedule_id,
    t.train_name,
    s.departure_time,
    t.total_seats,
    count(tk.ticket_id)                 AS seats_sold,
    t.total_seats - count(tk.ticket_id) AS seats_left
FROM schedules s
JOIN trains t       ON t.train_id = s.train_id
LEFT JOIN tickets tk ON tk.schedule_id = s.schedule_id AND tk.is_active
GROUP BY s.schedule_id, t.train_name, s.departure_time, t.total_seats
ORDER BY s.departure_time;


-- Q5. Revenue by payment method (refunds excluded)
SELECT
    payment_method,
    count(*)    AS payments,
    sum(amount) AS revenue
FROM payments
WHERE status = 'paid'
GROUP BY payment_method
ORDER BY revenue DESC;


-- Q6. Stations passed on a line, in order (replaces the hard-coded STRING_AGG)
SELECT
    l.line_name,
    string_agg(st.station_name, ' → ' ORDER BY ls.station_order) AS route
FROM line_stations ls
JOIN lines    l  ON l.line_id     = ls.line_id
JOIN stations st ON st.station_id = ls.station_id
GROUP BY l.line_name;


-- Q7. Journey planner with transfers (recursive CTE)
-- Finds every way to get from one station to another using up to 3 legs,
-- with at least 10 minutes to change trains, and AC trains only.
-- The course version hard-coded the two legs Nakhon Pathom -> Krung Thep
-- Aphiwat -> Don Mueang; this works for any pair of stations.
WITH RECURSIVE
params AS (
    SELECT
        'นครปฐม'::text   AS from_station,
        'ดอนเมือง'::text AS to_station,
        interval '10 minutes' AS min_transfer,
        3 AS max_legs
),
legs AS (   -- every scheduled AC trip, with readable names
    SELECT s.schedule_id, t.train_name,
           s.origin_station_id, s.destination_station_id,
           so.station_name AS origin_name, sd.station_name AS dest_name,
           s.departure_time, s.arrival_time, s.price
    FROM schedules s
    JOIN trains   t  ON t.train_id    = s.train_id
    JOIN stations so ON so.station_id = s.origin_station_id
    JOIN stations sd ON sd.station_id = s.destination_station_id
    WHERE t.train_type = 'AC'
),
journeys AS (
    -- first leg: leaves the starting station
    SELECT
        l.destination_station_id          AS at_station,
        l.dest_name                       AS at_name,
        l.departure_time                  AS start_time,
        l.arrival_time                    AS arrive_time,
        l.price::numeric                  AS total_price,
        1                                 AS n_legs,
        ARRAY[l.origin_station_id, l.destination_station_id] AS visited,
        l.train_name || ' (' || l.origin_name || ' → ' || l.dest_name || ')' AS itinerary
    FROM legs l, params p
    WHERE l.origin_name = p.from_station

    UNION ALL

    -- next leg: departs where the last one arrived, after the transfer buffer
    SELECT
        l.destination_station_id,
        l.dest_name,
        j.start_time,
        l.arrival_time,
        j.total_price + l.price,
        j.n_legs + 1,
        j.visited || l.destination_station_id,
        j.itinerary || '  ⇒  ' || l.train_name || ' (' || l.origin_name || ' → ' || l.dest_name || ')'
    FROM journeys j
    JOIN legs l ON l.origin_station_id = j.at_station
    CROSS JOIN params p
    WHERE l.departure_time >= j.arrive_time + p.min_transfer
      AND j.n_legs < p.max_legs
      AND NOT l.destination_station_id = ANY (j.visited)   -- no loops
)
SELECT
    itinerary,
    n_legs,
    start_time,
    arrive_time,
    arrive_time - start_time AS total_time,
    total_price
FROM journeys, params p
WHERE at_name = p.to_station
ORDER BY total_price, total_time;
