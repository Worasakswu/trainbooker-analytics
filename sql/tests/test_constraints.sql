-- =====================================================================
-- TrainBooker — constraint tests
-- Each test tries to insert BAD data and passes when the database rejects it.
-- If bad data gets in, the script stops with 'TEST FAILED'.
--
-- The tests create their own fixtures, so they pass on the small seed data
-- and on the large generated dataset alike. Everything runs in a transaction
-- that is rolled back, so the real data is never touched.
--
-- Run:  docker compose exec -T db psql -U trainbooker -d trainbooker -v ON_ERROR_STOP=1 -f /sql/tests/test_constraints.sql
-- =====================================================================
BEGIN;

-- helper: run a statement and require that it fails
CREATE FUNCTION pg_temp.expect_fail(test_name text, stmt text) RETURNS void AS $$
BEGIN
    EXECUTE stmt;
    RAISE EXCEPTION 'TEST FAILED: % (bad data was accepted)', test_name;
EXCEPTION
    WHEN raise_exception THEN
        IF SQLERRM LIKE 'TEST FAILED%' THEN RAISE; END IF;
        RAISE NOTICE 'PASS: % -> %', test_name, SQLERRM;
    WHEN others THEN
        RAISE NOTICE 'PASS: % -> %', test_name, SQLERRM;
END;
$$ LANGUAGE plpgsql;

-- ---------- fixtures ----------
-- a 2-seat train, two schedules on it, a user and a confirmed booking with seat T1
CREATE TEMP TABLE fx AS
WITH tr AS (
    INSERT INTO trains (train_name, train_type, total_seats)
    VALUES ('__test_train__', 'FAN', 2) RETURNING train_id
), us AS (
    INSERT INTO users (username, password_hash, full_name)
    VALUES ('__test_user__', crypt('secret-pw', gen_salt('bf')), 'Test User') RETURNING user_id
), sc AS (
    INSERT INTO schedules (train_id, origin_station_id, destination_station_id, departure_time, arrival_time, price)
    SELECT train_id, 1, 4, ts, ts + interval '1 hour', 50
    FROM tr, (VALUES ('2030-01-01 08:00+07'::timestamptz), ('2030-01-01 12:00+07'::timestamptz)) v(ts)
    RETURNING schedule_id, train_id, departure_time
)
SELECT
    (SELECT train_id FROM tr)                                   AS train_id,
    (SELECT user_id FROM us)                                    AS user_id,
    (SELECT schedule_id FROM sc ORDER BY departure_time LIMIT 1) AS sched_a,
    (SELECT schedule_id FROM sc ORDER BY departure_time DESC LIMIT 1) AS sched_b;

INSERT INTO bookings (user_id, schedule_id, status)
SELECT user_id, sched_a, 'confirmed' FROM fx;
ALTER TABLE fx ADD COLUMN booking_a int;
UPDATE fx SET booking_a = currval(pg_get_serial_sequence('bookings', 'booking_id'));
INSERT INTO tickets (booking_id, schedule_id, seat_number, passenger_name)
SELECT booking_a, sched_a, 'T1', 'Test User' FROM fx;

-- build a statement with fixture ids filled in: {user}, {train}, {a}, {b}, {booking}
CREATE FUNCTION pg_temp.q(stmt text) RETURNS text AS $$
    SELECT replace(replace(replace(replace(replace(stmt,
        '{user}', user_id::text), '{train}', train_id::text),
        '{a}', sched_a::text), '{b}', sched_b::text), '{booking}', booking_a::text)
    FROM fx;
$$ LANGUAGE sql;

-- ---------- tests ----------

-- 1. the same seat cannot be sold twice on one schedule
SELECT pg_temp.expect_fail('double-booked seat', pg_temp.q($q$
    INSERT INTO tickets (booking_id, schedule_id, seat_number, passenger_name)
    VALUES ({booking}, {a}, 'T1', 'Someone Else') $q$));

-- 2. a ticket's schedule must match its booking's schedule
SELECT pg_temp.expect_fail('ticket schedule does not match booking', pg_temp.q($q$
    INSERT INTO tickets (booking_id, schedule_id, seat_number, passenger_name)
    VALUES ({booking}, {b}, 'T9', 'Mismatch') $q$));

-- 3. a train cannot be oversold (2-seat train: T1 sold, T2 ok, T3 must fail)
INSERT INTO tickets (booking_id, schedule_id, seat_number, passenger_name)
SELECT booking_a, sched_a, 'T2', 'Second Seat' FROM fx;
SELECT pg_temp.expect_fail('oversold train', pg_temp.q($q$
    INSERT INTO tickets (booking_id, schedule_id, seat_number, passenger_name)
    VALUES ({booking}, {a}, 'T3', 'One Too Many') $q$));

-- 4. cancelling a booking releases its seats ...
UPDATE bookings SET status = 'cancelled' WHERE booking_id = (SELECT booking_a FROM fx);
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM tickets t JOIN fx ON t.booking_id = fx.booking_a WHERE t.is_active) THEN
        RAISE EXCEPTION 'TEST FAILED: cancelled booking still holds seats';
    END IF;
    RAISE NOTICE 'PASS: cancelling a booking released its seats';
END $$;

-- 5. ... and a released seat can be sold again
INSERT INTO bookings (user_id, schedule_id, status) SELECT user_id, sched_a, 'confirmed' FROM fx;
INSERT INTO tickets (booking_id, schedule_id, seat_number, passenger_name)
SELECT currval(pg_get_serial_sequence('bookings', 'booking_id')), sched_a, 'T1', 'Resold' FROM fx;
DO $$ BEGIN RAISE NOTICE 'PASS: released seat T1 was resold'; END $$;

-- 6. schedule rules
SELECT pg_temp.expect_fail('arrival before departure', pg_temp.q($q$
    INSERT INTO schedules (train_id, origin_station_id, destination_station_id, departure_time, arrival_time, price)
    VALUES ({train}, 1, 4, '2030-02-01 10:00+07', '2030-02-01 09:00+07', 100) $q$));
SELECT pg_temp.expect_fail('origin = destination', pg_temp.q($q$
    INSERT INTO schedules (train_id, origin_station_id, destination_station_id, departure_time, arrival_time, price)
    VALUES ({train}, 1, 1, '2030-02-01 10:00+07', '2030-02-01 11:00+07', 100) $q$));
SELECT pg_temp.expect_fail('duplicate schedule (same train, same departure)', pg_temp.q($q$
    INSERT INTO schedules (train_id, origin_station_id, destination_station_id, departure_time, arrival_time, price)
    VALUES ({train}, 1, 4, '2030-01-01 08:00+07', '2030-01-01 09:00+07', 50) $q$));
SELECT pg_temp.expect_fail('negative price', pg_temp.q($q$
    INSERT INTO schedules (train_id, origin_station_id, destination_station_id, departure_time, arrival_time, price)
    VALUES ({train}, 1, 4, '2030-03-01 10:00+07', '2030-03-01 11:00+07', -5) $q$));

-- 7. allowed values only
SELECT pg_temp.expect_fail('invalid booking status', pg_temp.q($q$
    INSERT INTO bookings (user_id, schedule_id, status) VALUES ({user}, {a}, 'Confirmed!!') $q$));
SELECT pg_temp.expect_fail('invalid payment method', pg_temp.q($q$
    INSERT INTO payments (booking_id, amount, payment_method) VALUES ({booking}, 100, 'bitcoin') $q$));
SELECT pg_temp.expect_fail('zero payment', pg_temp.q($q$
    INSERT INTO payments (booking_id, amount, payment_method) VALUES ({booking}, 0, 'cash') $q$));
SELECT pg_temp.expect_fail('invalid train type', $q$
    INSERT INTO trains (train_name, train_type, total_seats) VALUES ('__bad__', 'Steam', 10) $q$);

-- 8. passwords are never plain text, and bcrypt verifies
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM users WHERE password_hash NOT LIKE '$2a$%') THEN
        RAISE EXCEPTION 'TEST FAILED: a password is not a bcrypt hash';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM users
                   WHERE username = '__test_user__'
                     AND password_hash = crypt('secret-pw', password_hash)) THEN
        RAISE EXCEPTION 'TEST FAILED: bcrypt check did not verify';
    END IF;
    RAISE NOTICE 'PASS: all passwords are bcrypt hashes and verify correctly';
END $$;

ROLLBACK;
