-- =====================================================================
-- TrainBooker — profile the generated data
-- Quick checks that the patterns built into the generator really show up.
-- These are also the first questions the Phase 3 warehouse will answer.
--
-- Run:  docker compose exec -T db psql -U trainbooker -d trainbooker -f /sql/queries/data_profile.sql
-- =====================================================================

-- P1. Booking status mix
SELECT status, count(*) AS bookings,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
FROM bookings GROUP BY status ORDER BY bookings DESC;

-- P2. Seats sold by departure hour (expect morning + late-afternoon peaks)
SELECT extract(hour FROM s.departure_time)::int AS dep_hour,
       count(*) AS seats_sold
FROM tickets t JOIN schedules s USING (schedule_id)
WHERE t.is_active
GROUP BY 1 ORDER BY 1;

-- P3. Seats sold by day of week (expect Fri / Sun peaks)
SELECT extract(isodow FROM s.departure_time)::int || '-' || to_char(s.departure_time, 'Dy') AS weekday,
       round(count(*)::numeric / count(DISTINCT s.departure_time::date), 0) AS avg_seats_per_day
FROM tickets t JOIN schedules s USING (schedule_id)
WHERE t.is_active
GROUP BY 1 ORDER BY 1;

-- P4. Songkran: direction of travel around 13-15 April
SELECT s.departure_time::date AS travel_date,
       sum(CASE WHEN s.origin_station_id = 1      THEN 1 ELSE 0 END) AS leaving_bangkok,
       sum(CASE WHEN s.destination_station_id = 1 THEN 1 ELSE 0 END) AS returning_to_bangkok
FROM tickets t JOIN schedules s USING (schedule_id)
WHERE t.is_active
  AND s.departure_time::date BETWEEN '2026-04-07' AND '2026-04-20'
GROUP BY 1 ORDER BY 1;

-- P5. Busiest departures by occupancy
SELECT s.schedule_id, tr.train_name, s.departure_time,
       count(t.ticket_id) AS seats_sold, tr.total_seats,
       round(100.0 * count(t.ticket_id) / tr.total_seats, 1) AS occupancy_pct
FROM schedules s
JOIN trains tr USING (train_id)
LEFT JOIN tickets t ON t.schedule_id = s.schedule_id AND t.is_active
GROUP BY s.schedule_id, tr.train_name, s.departure_time, tr.total_seats
ORDER BY occupancy_pct DESC
LIMIT 10;

-- P6. How far ahead people book, and how often they cancel
SELECT CASE
         WHEN lead < interval '12 hours' THEN '1: < 12 hours'
         WHEN lead < interval '7 days'   THEN '2: 12h - 7 days'
         WHEN lead < interval '30 days'  THEN '3: 7 - 30 days'
         ELSE                                 '4: 30+ days'
       END AS lead_time,
       count(*) AS bookings,
       round(100.0 * avg((status = 'cancelled')::int), 1) AS cancel_rate_pct
FROM (SELECT b.status, s.departure_time - b.booked_at AS lead
      FROM bookings b JOIN schedules s USING (schedule_id)) x
GROUP BY 1 ORDER BY 1;

-- P7. Frequent travellers: share of bookings made by the top 10% of users
WITH per_user AS (
    SELECT user_id, count(*) AS n,
           ntile(10) OVER (ORDER BY count(*) DESC) AS decile
    FROM bookings GROUP BY user_id
)
SELECT round(100.0 * sum(n) FILTER (WHERE decile = 1) / sum(n), 1) AS top10pct_users_share_of_bookings
FROM per_user;

-- P8. Monthly revenue by payment method (paid only)
SELECT to_char(paid_at, 'YYYY-MM') AS month, payment_method, sum(amount) AS revenue
FROM payments WHERE status = 'paid'
GROUP BY 1, 2 ORDER BY 1, 3 DESC;
