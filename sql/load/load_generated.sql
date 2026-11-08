-- =====================================================================
-- TrainBooker — load generated CSVs into the OLTP database
--
-- Replaces all transactional data (users, schedules, bookings, tickets,
-- payments) with the CSVs in /data/generated. Reference data (lines,
-- stations, line_stations, trains) is kept.
--
-- Pattern: CSV -> temp staging table (\copy) -> typed INSERT into the real
-- table, so every constraint and trigger still checks the generated data.
-- The whole load is one transaction: it either fully succeeds or changes nothing.
--
-- Run (after `python generator/generate_data.py`):
--   docker compose exec -T db psql -U trainbooker -d trainbooker -v ON_ERROR_STOP=1 -f /sql/load/load_generated.sql
-- =====================================================================
\timing on
BEGIN;

TRUNCATE payments, tickets, bookings, schedules, users RESTART IDENTITY;

-- ---------- users ----------
CREATE TEMP TABLE stg_users (
    user_id int, username text, full_name text, email text, phone text, created_at timestamptz
) ON COMMIT DROP;
\copy stg_users FROM '/data/generated/users.csv' WITH (FORMAT csv, HEADER true)

-- every generated user gets the demo password 'demo1234' (hashed once, then shared)
INSERT INTO users (user_id, username, password_hash, full_name, email, phone, created_at)
OVERRIDING SYSTEM VALUE
SELECT s.user_id, s.username, h.hash, s.full_name, s.email, s.phone, s.created_at
FROM stg_users s
CROSS JOIN (SELECT crypt('demo1234', gen_salt('bf')) AS hash) h;

-- ---------- schedules ----------
CREATE TEMP TABLE stg_schedules (
    schedule_id int, train_id int, origin_station_id int, destination_station_id int,
    departure_time timestamptz, arrival_time timestamptz, price numeric(10,2)
) ON COMMIT DROP;
\copy stg_schedules FROM '/data/generated/schedules.csv' WITH (FORMAT csv, HEADER true)

INSERT INTO schedules (schedule_id, train_id, origin_station_id, destination_station_id,
                       departure_time, arrival_time, price)
OVERRIDING SYSTEM VALUE
SELECT * FROM stg_schedules;

-- ---------- bookings ----------
CREATE TEMP TABLE stg_bookings (
    booking_id int, user_id int, schedule_id int, status text, booked_at timestamptz
) ON COMMIT DROP;
\copy stg_bookings FROM '/data/generated/bookings.csv' WITH (FORMAT csv, HEADER true)

INSERT INTO bookings (booking_id, user_id, schedule_id, status, booked_at)
OVERRIDING SYSTEM VALUE
SELECT * FROM stg_bookings;

-- ---------- tickets (capacity trigger checks every row) ----------
CREATE TEMP TABLE stg_tickets (
    ticket_id int, booking_id int, schedule_id int, seat_number text, passenger_name text, is_active boolean
) ON COMMIT DROP;
\copy stg_tickets FROM '/data/generated/tickets.csv' WITH (FORMAT csv, HEADER true)

INSERT INTO tickets (ticket_id, booking_id, schedule_id, seat_number, passenger_name, is_active)
OVERRIDING SYSTEM VALUE
SELECT * FROM stg_tickets ORDER BY ticket_id;

-- ---------- payments ----------
CREATE TEMP TABLE stg_payments (
    payment_id int, booking_id int, amount numeric(10,2), payment_method text, status text, paid_at timestamptz
) ON COMMIT DROP;
\copy stg_payments FROM '/data/generated/payments.csv' WITH (FORMAT csv, HEADER true)

INSERT INTO payments (payment_id, booking_id, amount, payment_method, status, paid_at)
OVERRIDING SYSTEM VALUE
SELECT * FROM stg_payments;

-- ---------- move identity sequences past the loaded ids ----------
SELECT setval(pg_get_serial_sequence('users',     'user_id'),     max(user_id))     FROM users;
SELECT setval(pg_get_serial_sequence('schedules', 'schedule_id'), max(schedule_id)) FROM schedules;
SELECT setval(pg_get_serial_sequence('bookings',  'booking_id'),  max(booking_id))  FROM bookings;
SELECT setval(pg_get_serial_sequence('tickets',   'ticket_id'),   max(ticket_id))   FROM tickets;
SELECT setval(pg_get_serial_sequence('payments',  'payment_id'),  max(payment_id))  FROM payments;

COMMIT;
ANALYZE;

-- ---------- row counts ----------
SELECT 'users' AS table_name, count(*) AS rows FROM users
UNION ALL SELECT 'schedules', count(*) FROM schedules
UNION ALL SELECT 'bookings',  count(*) FROM bookings
UNION ALL SELECT 'tickets',   count(*) FROM tickets
UNION ALL SELECT 'payments',  count(*) FROM payments;
