-- =====================================================================
-- TrainBooker — seed data (small, hand-written sample)
-- Phase 2 will replace this with a generated dataset of 100k+ bookings.
--
-- Fixes from the course version:
--   * Krung Thep Aphiwat is one station shared by both lines
--   * duplicate schedule row (train 6, 09:00) removed
--   * booking 6 was charged 160 for a 110 ticket -> now 110
--   * pending booking 3 had a payment -> pending now means "not paid yet"
--   * cancelled booking 5 -> seat released, payment marked refunded
--   * demo passwords are hashed with bcrypt (they are all '1234')
-- =====================================================================

-- 1) lines
INSERT INTO lines (line_name) VALUES
('สายใต้'),     -- 1 Southern
('สายเหนือ');   -- 2 Northern

-- 2) stations (each station exactly once)
INSERT INTO stations (station_name, province) VALUES
('กรุงเทพอภิวัฒน์', 'กรุงเทพมหานคร'),  -- 1 interchange
('ตลิ่งชัน',       'กรุงเทพมหานคร'),  -- 2
('ศาลายา',        'นครปฐม'),         -- 3
('นครปฐม',        'นครปฐม'),         -- 4
('บางซื่อ',        'กรุงเทพมหานคร'),  -- 5
('ดอนเมือง',       'กรุงเทพมหานคร'),  -- 6
('หลักสี่',         'กรุงเทพมหานคร'),  -- 7
('เชียงราก',       'ปทุมธานี'),        -- 8
('ปทุมธานี',       'ปทุมธานี');        -- 9

-- 3) station order on each line
INSERT INTO line_stations (line_id, station_id, station_order) VALUES
(1, 1, 1), (1, 2, 2), (1, 3, 3), (1, 4, 4),
(2, 1, 1), (2, 5, 2), (2, 6, 3), (2, 7, 4), (2, 8, 5), (2, 9, 6);

-- 4) users (password for every demo user = '1234')
INSERT INTO users (username, password_hash, full_name, email, phone, created_at) VALUES
('user01', crypt('1234', gen_salt('bf')), 'Somchai', 'somchai@email.com', '0811111111', '2026-02-01 10:00+07'),
('user02', crypt('1234', gen_salt('bf')), 'Anan',    'anan@email.com',    '0822222222', '2026-02-03 12:30+07'),
('user03', crypt('1234', gen_salt('bf')), 'Suda',    'suda@email.com',    '0833333333', '2026-02-05 09:15+07'),
('user04', crypt('1234', gen_salt('bf')), 'Wichai',  'wichai@email.com',  '0844444444', '2026-02-10 18:45+07'),
('user05', crypt('1234', gen_salt('bf')), 'Mana',    'mana@email.com',    '0855555555', '2026-02-14 20:00+07'),
('user06', crypt('1234', gen_salt('bf')), 'Jane',    'jane@email.com',    '0866666666', '2026-02-20 07:30+07');

-- 5) trains
INSERT INTO trains (train_name, train_type, total_seats) VALUES
('South Express', 'AC',  500),  -- 1
('North Local',   'FAN', 350),  -- 2
('North Express', 'AC',  450),  -- 3
('South Local',   'FAN', 300),  -- 4
('InterCity',     'AC',  550),  -- 5
('Rapid North',   'AC',  420);  -- 6

-- 6) schedules
INSERT INTO schedules
(train_id, origin_station_id, destination_station_id, departure_time, arrival_time, price)
VALUES
-- Southern line, outbound (Krung Thep Aphiwat -> Nakhon Pathom)
(1, 1, 4, '2026-03-10 08:00+07', '2026-03-10 09:30+07', 120),  -- 1
(4, 1, 4, '2026-03-10 08:45+07', '2026-03-10 10:15+07', 100),  -- 2
(5, 1, 4, '2026-03-10 09:30+07', '2026-03-10 11:00+07', 150),  -- 3
-- Southern line, return
(1, 4, 1, '2026-03-10 12:00+07', '2026-03-10 13:30+07', 120),  -- 4
(4, 4, 1, '2026-03-10 12:45+07', '2026-03-10 14:15+07', 100),  -- 5
(5, 4, 1, '2026-03-10 13:30+07', '2026-03-10 15:00+07', 150),  -- 6
-- Northern line, outbound
(2, 1, 9, '2026-03-10 07:30+07', '2026-03-10 08:40+07',  80),  -- 7
(3, 1, 6, '2026-03-10 15:30+07', '2026-03-10 16:00+07',  90),  -- 8
(6, 1, 6, '2026-03-10 16:00+07', '2026-03-10 16:30+07', 110),  -- 9
(3, 1, 9, '2026-03-10 08:15+07', '2026-03-10 09:25+07', 140),  -- 10
(6, 1, 9, '2026-03-10 09:00+07', '2026-03-10 10:10+07', 160),  -- 11
-- Northern line, return
(2, 9, 1, '2026-03-10 11:30+07', '2026-03-10 12:40+07',  80),  -- 12
(3, 9, 1, '2026-03-10 12:15+07', '2026-03-10 13:25+07', 140),  -- 13
(6, 9, 1, '2026-03-10 13:00+07', '2026-03-10 14:10+07', 160);  -- 14

-- 7) bookings
INSERT INTO bookings (user_id, schedule_id, status, booked_at) VALUES
(1, 1, 'confirmed', '2026-03-01 10:12+07'),  -- 1
(2, 2, 'confirmed', '2026-03-02 14:40+07'),  -- 2
(3, 4, 'pending',   '2026-03-09 21:05+07'),  -- 3
(4, 5, 'confirmed', '2026-03-05 08:20+07'),  -- 4
(5, 7, 'cancelled', '2026-03-03 19:55+07'),  -- 5
(6, 9, 'confirmed', '2026-03-08 11:30+07');  -- 6

-- 8) tickets (schedule_id must match the booking's schedule — enforced by FK)
INSERT INTO tickets (booking_id, schedule_id, seat_number, passenger_name, is_active) VALUES
(1, 1, 'A01', 'Somchai', TRUE),
(2, 2, 'A02', 'Anan',    TRUE),
(3, 4, 'B01', 'Suda',    TRUE),   -- seat held while pending
(4, 5, 'B02', 'Wichai',  TRUE),
(5, 7, 'C01', 'Mana',    FALSE),  -- cancelled -> seat released
(6, 9, 'C02', 'Jane',    TRUE);

-- 9) payments
INSERT INTO payments (booking_id, amount, payment_method, status, paid_at) VALUES
(1, 120, 'qr_code',        'paid',     '2026-03-01 10:15+07'),
(2, 100, 'cash',           'paid',     '2026-03-02 14:45+07'),
(4, 100, 'mobile_banking', 'paid',     '2026-03-05 08:22+07'),
(5,  80, 'qr_code',        'refunded', '2026-03-03 20:00+07'),
(6, 110, 'cash',           'paid',     '2026-03-08 11:35+07');
