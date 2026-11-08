-- =====================================================================
-- TrainBooker — OLTP schema (PostgreSQL 16)
-- Phase 1: hardened version of the original DB course schema.
--
-- Changes from the course version:
--   * snake_case identifiers (no quoting needed, dbt-friendly)
--   * stations are unique; which line a station belongs to (and its order)
--     lives in line_stations, so an interchange like Krung Thep Aphiwat is
--     ONE station on TWO lines instead of two duplicate rows
--   * CHECK constraints for statuses, prices, and time ordering
--   * a seat cannot be sold twice on the same schedule (partial unique index)
--   * a trigger blocks tickets beyond the train's total seats
--   * passwords stored as bcrypt hashes (pgcrypto), never plain text
--   * created_at / booked_at / paid_at audit timestamps
--   * indexes on every foreign key
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------- reference data ----------

CREATE TABLE lines (
    line_id    INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    line_name  VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE stations (
    station_id    INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    station_name  VARCHAR(100) NOT NULL UNIQUE,
    province      VARCHAR(100)
);

-- which stations are on which line, in order
CREATE TABLE line_stations (
    line_id        INT NOT NULL REFERENCES lines(line_id),
    station_id     INT NOT NULL REFERENCES stations(station_id),
    station_order  INT NOT NULL CHECK (station_order > 0),
    PRIMARY KEY (line_id, station_id),
    UNIQUE (line_id, station_order)
);
CREATE INDEX idx_line_stations_station ON line_stations(station_id);

CREATE TABLE trains (
    train_id     INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    train_name   VARCHAR(100) NOT NULL UNIQUE,
    train_type   VARCHAR(20)  NOT NULL CHECK (train_type IN ('AC', 'FAN')),
    total_seats  INT          NOT NULL CHECK (total_seats > 0)
);

-- ---------- users ----------

CREATE TABLE users (
    user_id        INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    username       VARCHAR(50)  NOT NULL UNIQUE,
    password_hash  TEXT         NOT NULL,          -- bcrypt via crypt()
    full_name      VARCHAR(100),
    email          VARCHAR(100) UNIQUE,
    phone          VARCHAR(15),
    created_at     TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- ---------- schedules ----------

CREATE TABLE schedules (
    schedule_id             INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    train_id                INT NOT NULL REFERENCES trains(train_id),
    origin_station_id       INT NOT NULL REFERENCES stations(station_id),
    destination_station_id  INT NOT NULL REFERENCES stations(station_id),
    departure_time          TIMESTAMPTZ   NOT NULL,
    arrival_time            TIMESTAMPTZ   NOT NULL,
    price                   NUMERIC(10,2) NOT NULL CHECK (price >= 0),
    CHECK (origin_station_id <> destination_station_id),
    CHECK (arrival_time > departure_time),
    -- a train cannot depart twice at the same moment (blocks duplicate rows)
    UNIQUE (train_id, departure_time)
);
CREATE INDEX idx_schedules_train       ON schedules(train_id);
CREATE INDEX idx_schedules_origin      ON schedules(origin_station_id);
CREATE INDEX idx_schedules_destination ON schedules(destination_station_id);
CREATE INDEX idx_schedules_departure   ON schedules(departure_time);

-- ---------- bookings / tickets / payments ----------

CREATE TABLE bookings (
    booking_id   INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id      INT NOT NULL REFERENCES users(user_id),
    schedule_id  INT NOT NULL REFERENCES schedules(schedule_id),
    status       VARCHAR(20) NOT NULL DEFAULT 'pending'
                 CHECK (status IN ('pending', 'confirmed', 'cancelled')),
    booked_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- lets tickets reference (booking_id, schedule_id) together
    UNIQUE (booking_id, schedule_id)
);
CREATE INDEX idx_bookings_user     ON bookings(user_id);
CREATE INDEX idx_bookings_schedule ON bookings(schedule_id);

-- schedule_id is copied onto the ticket (and kept consistent by the
-- composite FK) so the database itself can enforce one seat per schedule
CREATE TABLE tickets (
    ticket_id       INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    booking_id      INT NOT NULL,
    schedule_id     INT NOT NULL,
    seat_number     VARCHAR(10)  NOT NULL,
    passenger_name  VARCHAR(100) NOT NULL,
    is_active       BOOLEAN      NOT NULL DEFAULT TRUE,  -- FALSE = seat released
    FOREIGN KEY (booking_id, schedule_id)
        REFERENCES bookings(booking_id, schedule_id)
);
CREATE INDEX idx_tickets_booking ON tickets(booking_id);
-- the key rule: an active seat can only be sold once per schedule
CREATE UNIQUE INDEX uq_tickets_active_seat
    ON tickets(schedule_id, seat_number) WHERE is_active;

CREATE TABLE payments (
    payment_id      INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    booking_id      INT NOT NULL REFERENCES bookings(booking_id),
    amount          NUMERIC(10,2) NOT NULL CHECK (amount > 0),
    payment_method  VARCHAR(20) NOT NULL
                    CHECK (payment_method IN ('qr_code', 'cash', 'credit_card', 'mobile_banking')),
    status          VARCHAR(20) NOT NULL DEFAULT 'paid'
                    CHECK (status IN ('paid', 'failed', 'refunded')),
    paid_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_payments_booking ON payments(booking_id);

-- ---------- business rules ----------

-- 1) block selling more active tickets than the train has seats
CREATE FUNCTION check_seat_capacity() RETURNS trigger AS $$
DECLARE
    v_capacity INT;
    v_sold     INT;
BEGIN
    IF NOT NEW.is_active THEN
        RETURN NEW;
    END IF;

    SELECT t.total_seats INTO v_capacity
    FROM schedules s JOIN trains t ON t.train_id = s.train_id
    WHERE s.schedule_id = NEW.schedule_id
    FOR UPDATE OF s;          -- serialize concurrent sales on one schedule

    SELECT count(*) INTO v_sold
    FROM tickets
    WHERE schedule_id = NEW.schedule_id
      AND is_active
      AND ticket_id IS DISTINCT FROM NEW.ticket_id;

    IF v_sold >= v_capacity THEN
        RAISE EXCEPTION 'schedule % is full (% seats)', NEW.schedule_id, v_capacity;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_tickets_capacity
    BEFORE INSERT OR UPDATE OF is_active, schedule_id ON tickets
    FOR EACH ROW EXECUTE FUNCTION check_seat_capacity();

-- 2) cancelling a booking releases its seats automatically
CREATE FUNCTION release_seats_on_cancel() RETURNS trigger AS $$
BEGIN
    IF NEW.status = 'cancelled' AND OLD.status <> 'cancelled' THEN
        UPDATE tickets SET is_active = FALSE WHERE booking_id = NEW.booking_id;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_bookings_cancel
    AFTER UPDATE OF status ON bookings
    FOR EACH ROW EXECUTE FUNCTION release_seats_on_cancel();
