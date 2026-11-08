# TrainBooker Analytics

A train-ticket booking database for Thai rail routes, being extended step by step into an end-to-end data engineering project: from a hardened **OLTP database** to a **star-schema warehouse**, **data-quality tests**, **orchestration** and a **dashboard**.

> This project started as a group assignment for the Database course (CP242) at Srinakharinwirot University. See [Credits](#credits).

## Roadmap

| Phase | What | Status |
|---|---|---|
| 1 | Harden the OLTP schema: constraints, triggers, hashed passwords, Docker | ✅ Done |
| 2 | Generate realistic data (100k bookings) and bulk-load it, with data-quality checks | ✅ Done |
| 3 | ELT into a star-schema warehouse with dbt + data-quality tests | ⏳ Next |
| 4 | Orchestration (Airflow) + CI with GitHub Actions | Planned |
| 5 | Dashboard: occupancy, route revenue, cancellation rate | Planned |

## Quick start

Requires Docker and Python 3.10+ (standard library only — nothing to `pip install`).

```bash
./scripts/run_pipeline.sh
```

This one command:
1. starts Postgres 16 on `localhost:5433` (schema + small seed data load on first start)
2. generates ~100k bookings as CSV files (`data/generated/`)
3. loads them into Postgres in a single transaction (~8 s)
4. runs the constraint tests and data-quality checks

Then explore:

```bash
docker compose exec -T db psql -U trainbooker -d trainbooker -f /sql/queries/data_profile.sql
docker compose exec -T db psql -U trainbooker -d trainbooker -f /sql/queries/example_queries.sql
```

Generator options: `./scripts/run_pipeline.sh --bookings 20000 --users 3000 --seed 7`.
The same `--seed` always produces exactly the same data.

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

## Synthetic data (Phase 2)

[`generator/generate_data.py`](generator/generate_data.py) simulates six months of bookings (Jan–Jun 2026) with patterns that later analytics can discover:

| Pattern | What the data shows (default seed) |
|---|---|
| Rush hours | Each morning departure (07:30–09:30) sells 1.6–1.9× the seats of the 11:30 train |
| Weekly cycle | Fridays (~1,000 seats/day) and Sundays (~980) vs. Tuesdays (~620) |
| Songkran | 1,500–2,100 people/day leave Bangkok on 10–12 Apr (~4× a normal day); the return rush peaks on 17 Apr |
| Sell-outs | Cheaper FAN trains on Songkran mornings reach 100% occupancy; extra demand is turned away |
| Booking lead time | Most people book within a week; holiday trips are booked earlier |
| Cancellations | 13% for bookings made 7+ days ahead vs. 5% for last-minute bookings |
| Heavy users | The top 10% of users make ~45% of all bookings (Pareto) |

**Pipeline:** Python writes CSVs → `\copy` into temporary staging tables → typed `INSERT` into the real tables. Loading through the real tables means every constraint and trigger (including the seat-capacity trigger) checks all 150k tickets. The whole load runs in one transaction, so a failure leaves the database unchanged.

**Data-quality checks** ([`sql/tests/test_data_quality.sql`](sql/tests/test_data_quality.sql)) cover rules that span several tables, which table constraints can't express. For example: a booking is made before departure and after the user signed up, every confirmed booking is paid exactly once, refunds only happen on cancelled bookings, and the payment amount equals price × seats.

| Table | Rows |
|---|---|
| users | 8,000 |
| schedules | 2,534 |
| bookings | ~99,700 |
| tickets | ~152,600 |
| payments | ~98,500 |

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
├── scripts/run_pipeline.sh   # generate -> load -> test, in one command
├── generator/
│   └── generate_data.py      # synthetic booking history -> CSV
├── data/generated/           # CSV output (git-ignored, reproducible)
├── sql/
│   ├── init/                 # 01_schema.sql, 02_seed.sql — loaded automatically by Docker
│   ├── load/                 # load_generated.sql — CSV -> staging -> tables
│   ├── queries/              # example_queries.sql, data_profile.sql
│   └── tests/                # test_constraints.sql, test_data_quality.sql
└── docs/                     # ERD and original course materials
```

## Credits

The original TrainBooker database (Phase 0) was designed for the Database course (CP242) at Srinakharinwirot University by:

- Kritchatrin Boonsoo
- Nathaphon Suanyai
- Worasak Sankla

Phases 1 onward are developed by Worasak Sankla.
