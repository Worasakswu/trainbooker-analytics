-- =====================================================================
-- TrainBooker — data quality checks
-- Business rules that span several tables, which table constraints can't
-- express. Each check counts violating rows; the script fails if any > 0.
-- (In Phase 3 these become dbt tests.)
--
-- Run:  docker compose exec -T db psql -U trainbooker -d trainbooker -v ON_ERROR_STOP=1 -f /sql/tests/test_data_quality.sql
-- =====================================================================
CREATE TEMP TABLE dq_results (check_name text, violations bigint);

INSERT INTO dq_results
-- a booking must be made before the train leaves
SELECT 'booked before departure', count(*)
FROM bookings b JOIN schedules s USING (schedule_id)
WHERE b.booked_at >= s.departure_time

-- a user can't book before they signed up
UNION ALL
SELECT 'user existed when booking', count(*)
FROM bookings b JOIN users u USING (user_id)
WHERE b.booked_at < u.created_at

-- every booking has at least one ticket
UNION ALL
SELECT 'booking has tickets', count(*)
FROM bookings b
WHERE NOT EXISTS (SELECT 1 FROM tickets t WHERE t.booking_id = b.booking_id)

-- tickets of cancelled bookings are released; others are active
UNION ALL
SELECT 'ticket active flag matches booking status', count(*)
FROM tickets t JOIN bookings b USING (booking_id)
WHERE t.is_active <> (b.status <> 'cancelled')

-- active tickets never exceed train capacity
UNION ALL
SELECT 'schedule not oversold', count(*)
FROM (
    SELECT s.schedule_id
    FROM schedules s
    JOIN trains tr USING (train_id)
    JOIN tickets t ON t.schedule_id = s.schedule_id AND t.is_active
    GROUP BY s.schedule_id, tr.total_seats
    HAVING count(*) > tr.total_seats
) x

-- every confirmed booking has exactly one successful payment
UNION ALL
SELECT 'confirmed booking paid exactly once', count(*)
FROM bookings b
WHERE b.status = 'confirmed'
  AND (SELECT count(*) FROM payments p WHERE p.booking_id = b.booking_id AND p.status = 'paid') <> 1

-- pending / cancelled bookings never keep a successful payment
UNION ALL
SELECT 'no paid payment on pending/cancelled', count(*)
FROM payments p JOIN bookings b USING (booking_id)
WHERE p.status = 'paid' AND b.status <> 'confirmed'

-- refunds only happen on cancelled bookings
UNION ALL
SELECT 'refund only on cancelled', count(*)
FROM payments p JOIN bookings b USING (booking_id)
WHERE p.status = 'refunded' AND b.status <> 'cancelled'

-- amount = ticket price x number of seats
UNION ALL
SELECT 'payment amount = price x seats', count(*)
FROM payments p
JOIN bookings  b USING (booking_id)
JOIN schedules s USING (schedule_id)
WHERE p.amount <> s.price * (SELECT count(*) FROM tickets t WHERE t.booking_id = b.booking_id)

-- payment happens after the booking
UNION ALL
SELECT 'paid after booking', count(*)
FROM payments p JOIN bookings b USING (booking_id)
WHERE p.paid_at < b.booked_at;

SELECT check_name,
       violations,
       CASE WHEN violations = 0 THEN 'PASS' ELSE 'FAIL' END AS result
FROM dq_results;

DO $$
DECLARE n int;
BEGIN
    SELECT count(*) INTO n FROM dq_results WHERE violations > 0;
    IF n > 0 THEN
        RAISE EXCEPTION 'DATA QUALITY FAILED: % check(s) have violations', n;
    END IF;
    RAISE NOTICE 'ALL DATA QUALITY CHECKS PASSED';
END $$;
