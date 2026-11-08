# TrainBooker Analytics

A train-ticket booking database for Thai rail routes, being extended step by step into an end-to-end data engineering project: from a hardened **OLTP database** to a **star-schema warehouse**, **data-quality tests**, **orchestration** and a **dashboard**.

> This project started as a group assignment for the Database course (CP242) at Srinakharinwirot University. See [Credits](#credits).

## Roadmap

| Phase | What | Status |
|---|---|---|
| 1 | Harden the OLTP schema: constraints, triggers, hashed passwords, Docker | ✅ Done |
| 2 | Generate realistic data (100k+ bookings) with Python + Faker | ⏳ Next |
| 3 | ELT into a star-schema warehouse with dbt + data-quality tests | Planned |
| 4 | Orchestration (Airflow) + CI with GitHub Actions | Planned |
| 5 | Dashboard: occupancy, route revenue, cancellation rate | Planned |

## Quick start

Requires Docker.

```bash
docker compose up -d          # starts Postgres 16 on localhost:5433 and loads schema + seed data

# run the constraint tests (all should print PASS)
docker compose exec -T db psql -U trainbooker -d trainbooker -v ON_ERROR_STOP=1 < sql/tests/test_constraints.sql

# run the example queries
docker compose exec -T db psql -U trainbooker -d trainbooker < sql/queries/example_queries.sql
```

To reset the database from scratch: `docker compose down -v && docker compose up -d`.

## Data model

```
lines ──< line_stations >── stations
                               │  (origin / destination)
trains ──< schedules >─────────┘
              │
users ──< bookings ──< tickets
              │
              └──< payments
```

| Table | Purpose |
|---|---|
| `lines`, `stations`, `line_stations` | Rail lines and the ordered stations on each. An interchange (Krung Thep Aphiwat) is one station on two lines. |
| `trains` | Train name, type (`AC` / `FAN`) and seat capacity |
| `schedules` | A train running from one station to another at a set time and price |
| `users` | Customers; passwords stored as bcrypt hashes |
| `bookings` | A user's booking on a schedule: `pending` → `confirmed` / `cancelled` |
| `tickets` | One seat for one passenger on a booking |
| `payments` | `paid` / `failed` / `refunded` payments for a booking |

## Business rules enforced by the database

| Rule | How |
|---|---|
| A seat can't be sold twice on the same schedule | Partial unique index on `(schedule_id, seat_number) WHERE is_active` |
| A train can't be oversold | `BEFORE INSERT` trigger compares active tickets with `total_seats`, locking the schedule row to handle concurrent sales |
| Cancelling a booking frees its seats | `AFTER UPDATE` trigger sets the booking's tickets to `is_active = false` |
| A ticket belongs to the same schedule as its booking | Composite foreign key `(booking_id, schedule_id)` |
| No duplicate schedules | `UNIQUE (train_id, departure_time)` |
| Valid times, prices and statuses | `CHECK` constraints (arrival > departure, origin ≠ destination, price ≥ 0, allowed status values) |
| No plain-text passwords | `pgcrypto` `crypt()` with bcrypt |

All of these are covered by [`sql/tests/test_constraints.sql`](sql/tests/test_constraints.sql), which tries to insert bad data and checks that the database rejects it.

## Highlight: journey planner with transfers

[`sql/queries/example_queries.sql`](sql/queries/example_queries.sql) Q7 uses a **recursive CTE** to find every route between two stations, including changes between lines, with a minimum transfer time. Example: Nakhon Pathom → Don Mueang on AC trains only:

| Itinerary | Legs | Total time | Price (THB) |
|---|---|---|---|
| South Express (Nakhon Pathom → Krung Thep Aphiwat) ⇒ North Express (→ Don Mueang) | 2 | 4:00 | 210 |
| InterCity (Nakhon Pathom → Krung Thep Aphiwat) ⇒ North Express (→ Don Mueang) | 2 | 2:30 | 240 |

The course version answered this with hard-coded station names for one route; this version works for any pair of stations.

## What changed from the course version

- Fixed a column-name mismatch (`Locations` vs `Location`) that made the original script fail
- Normalized stations so a shared station isn't stored twice
- Removed a duplicate schedule row and fixed inconsistent seed data (payment amount ≠ ticket price, payment recorded for a pending booking)
- Added constraints, triggers, indexes, audit timestamps (`created_at`, `booked_at`, `paid_at`) and hashed passwords
- Switched to `snake_case` names and `TIMESTAMPTZ` (Asia/Bangkok)
- Added Docker setup and automated constraint tests

## Project structure

```
├── docker-compose.yml
├── sql/
│   ├── init/        # 01_schema.sql, 02_seed.sql — loaded automatically by Docker
│   ├── queries/     # example and analytical queries
│   └── tests/       # constraint tests
└── docs/            # ERD and original course materials
```

## Credits

The original TrainBooker database (Phase 0) was designed for the Database course (CP242) at Srinakharinwirot University by:

- Kritchatrin Boonsoo
- Nathaphon Suanyai
- Worasak Sankla

Phases 1 onward are developed by Worasak Sankla.
