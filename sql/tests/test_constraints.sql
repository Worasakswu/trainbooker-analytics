-- =====================================================================
-- TrainBooker — constraint tests
-- Each block tries to insert BAD data. The test passes when the database
-- rejects it. If bad data gets in, the block raises 'TEST FAILED'.
-- Everything runs in a transaction that is rolled back, so the data is untouched.
--
-- Run:  docker compose exec -T db psql -U trainbooker -d trainbooker -v ON_ERROR_STOP=1 < sql/tests/test_constraints.sql
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

-- 1. the same seat cannot be sold twice on one schedule
SELECT pg_temp.expect_fail('double-booked seat',
  $q$ INSERT INTO tickets (booking_id, schedule_id, seat_number, passenger_name)
      VALUES (1, 1, 'A01', 'Someone Else') $q$);

-- 2. ...but a seat released by a cancellation CAN be sold again
INSERT INTO bookings (user_id, schedule_id, status) VALUES (1, 7, 'confirmed');
INSERT INTO tickets (booking_id, schedule_id, seat_number, passenger_name)
VALUES (currval(pg_get_serial_sequence('bookings', 'booking_id')), 7, 'C01', 'Resold OK');
SELECT 'PASS: released seat C01 on schedule 7 can be resold' AS result;

-- 3. a ticket's schedule must match its booking's schedule
SELECT pg_temp.expect_fail('ticket schedule does not match booking',
  $q$ INSERT INTO tickets (booking_id, schedule_id, seat_number, passenger_name)
      VALUES (1, 2, 'Z99', 'Mismatch') $q$);

-- 4. arrival must be after departure
SELECT pg_temp.expect_fail('arrival before departure',
  $q$ INSERT INTO schedules (train_id, origin_station_id, destination_station_id, departure_time, arrival_time, price)
      VALUES (1, 1, 4, '2026-04-01 10:00+07', '2026-04-01 09:00+07', 100) $q$);

-- 5. origin and destination must differ
SELECT pg_temp.expect_fail('origin = destination',
  $q$ INSERT INTO schedules (train_id, origin_station_id, destination_station_id, departure_time, arrival_time, price)
      VALUES (1, 1, 1, '2026-04-01 10:00+07', '2026-04-01 11:00+07', 100) $q$);

-- 6. duplicate schedule (same train, same departure)
SELECT pg_temp.expect_fail('duplicate schedule',
  $q$ INSERT INTO schedules (train_id, origin_station_id, destination_station_id, departure_time, arrival_time, price)
      VALUES (6, 1, 9, '2026-03-10 09:00+07', '2026-03-10 10:10+07', 160) $q$);

-- 7. invalid status values
SELECT pg_temp.expect_fail('invalid booking status',
  $q$ INSERT INTO bookings (user_id, schedule_id, status) VALUES (1, 1, 'Confirmed!!') $q$);
SELECT pg_temp.expect_fail('invalid payment method',
  $q$ INSERT INTO payments (booking_id, amount, payment_method) VALUES (1, 100, 'bitcoin') $q$);

-- 8. negative price / zero payment
SELECT pg_temp.expect_fail('negative price',
  $q$ INSERT INTO schedules (train_id, origin_station_id, destination_station_id, departure_time, arrival_time, price)
      VALUES (1, 1, 4, '2026-04-02 10:00+07', '2026-04-02 11:00+07', -5) $q$);
SELECT pg_temp.expect_fail('zero payment',
  $q$ INSERT INTO payments (booking_id, amount, payment_method) VALUES (1, 0, 'cash') $q$);

-- 9. a train cannot be oversold (capacity trigger)
INSERT INTO trains (train_name, train_type, total_seats) VALUES ('Tiny Test Train', 'FAN', 2);
INSERT INTO schedules (train_id, origin_station_id, destination_station_id, departure_time, arrival_time, price)
VALUES ((SELECT train_id FROM trains WHERE train_name = 'Tiny Test Train'),
        1, 4, '2026-05-01 08:00+07', '2026-05-01 09:00+07', 50);
INSERT INTO bookings (user_id, schedule_id, status)
VALUES (1, currval(pg_get_serial_sequence('schedules', 'schedule_id')), 'confirmed');
INSERT INTO tickets (booking_id, schedule_id, seat_number, passenger_name)
SELECT b.booking_id, b.schedule_id, seat, 'p'
FROM (SELECT currval(pg_get_serial_sequence('bookings', 'booking_id')) AS booking_id,
             currval(pg_get_serial_sequence('schedules', 'schedule_id')) AS schedule_id) b,
     unnest(ARRAY['01', '02']) AS seat;
SELECT pg_temp.expect_fail('oversold train (3rd ticket on a 2-seat train)',
  format($q$ INSERT INTO tickets (booking_id, schedule_id, seat_number, passenger_name)
             VALUES (%s, %s, '03', 'p') $q$,
         currval(pg_get_serial_sequence('bookings', 'booking_id')),
         currval(pg_get_serial_sequence('schedules', 'schedule_id'))));

-- 10. cancelling a booking releases its seats
UPDATE bookings SET status = 'cancelled' WHERE booking_id = 1;
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM tickets WHERE booking_id = 1 AND is_active) THEN
        RAISE EXCEPTION 'TEST FAILED: cancelled booking still holds seats';
    END IF;
    RAISE NOTICE 'PASS: cancelling booking 1 released its seats';
END $$;

-- 11. passwords are never stored in plain text, and the hash verifies
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM users WHERE password_hash = '1234') THEN
        RAISE EXCEPTION 'TEST FAILED: plain-text password found';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM users
                   WHERE username = 'user01'
                     AND password_hash = crypt('1234', password_hash)) THEN
        RAISE EXCEPTION 'TEST FAILED: bcrypt check for user01 did not verify';
    END IF;
    RAISE NOTICE 'PASS: passwords are bcrypt hashes and verify correctly';
END $$;

ROLLBACK;
