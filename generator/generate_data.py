"""
TrainBooker synthetic data generator.

Creates a realistic booking history as CSV files, using only the Python
standard library (no pip install needed). The CSVs are then loaded into
Postgres by sql/load/load_generated.sql.

Patterns built into the data (so later analytics have something to find):
  * morning (07-09) and late-afternoon (15-17) peaks
  * Friday / Sunday travel peaks, quieter mid-week
  * Songkran: outbound rush from Bangkok before the holiday, return rush after
  * New Year return rush into Bangkok
  * cheaper FAN trains attract more demand per departure
  * a small group of frequent travellers makes many of the bookings (Pareto)
  * most people book within a week; holiday trips are booked earlier
  * bookings made far in advance are cancelled more often
  * popular departures can sell out; demand beyond capacity is turned away

Usage:
    python generator/generate_data.py                       # defaults: 100k bookings
    python generator/generate_data.py --bookings 20000 --seed 7
"""

from __future__ import annotations

import argparse
import bisect
import csv
import math
import random
from collections import Counter, defaultdict
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

BKK = timezone(timedelta(hours=7))

# ---------------------------------------------------------------------------
# Reference data — must match sql/init/02_seed.sql
# ---------------------------------------------------------------------------
BANGKOK = 1  # station_id of กรุงเทพอภิวัฒน์

TRAIN_CAPACITY = {1: 500, 2: 350, 3: 450, 4: 300, 5: 550, 6: 420}
TRAIN_TYPE = {1: "AC", 2: "FAN", 3: "AC", 4: "FAN", 5: "AC", 6: "AC"}

# Daily timetable: (train_id, origin, destination, departure "HH:MM", minutes, price)
TIMETABLE = [
    (1, 1, 4, "08:00", 90, 120),
    (4, 1, 4, "08:45", 90, 100),
    (5, 1, 4, "09:30", 90, 150),
    (1, 4, 1, "12:00", 90, 120),
    (4, 4, 1, "12:45", 90, 100),
    (5, 4, 1, "13:30", 90, 150),
    (2, 1, 9, "07:30", 70, 80),
    (3, 1, 6, "15:30", 30, 90),
    (6, 1, 6, "16:00", 30, 110),
    (3, 1, 9, "08:15", 70, 140),
    (6, 1, 9, "09:00", 70, 160),
    (2, 9, 1, "11:30", 70, 80),
    (3, 9, 1, "12:15", 70, 140),
    (6, 9, 1, "13:00", 70, 160),
]

FIRST_NAMES = [
    "สมชาย", "สมหญิง", "อนันต์", "สุดา", "วิชัย", "มานะ", "ปิยะ", "กมล", "ธนา", "ณัฐพล",
    "ศิริพร", "พิมพ์ชนก", "จิราพร", "อรุณ", "ชัยวัฒน์", "สุรเชษฐ์", "วรรณา", "ปรีชา", "นภา", "กิตติ",
    "ธีรพงษ์", "อัญชลี", "ภัทรา", "วีระ", "รัตนา", "สุนทร", "เกศินี", "ประเสริฐ", "ดวงใจ", "ณัฐธิดา",
    "ภานุวัฒน์", "ชนิดา", "ศักดิ์ชัย", "อำไพ", "ธนพร", "วรากร", "พงศกร", "ปวีณา", "จักรพันธ์", "สิริกร",
]
LAST_NAMES = [
    "ใจดี", "ศรีสุข", "บุญมา", "แก้วกล้า", "สุขสวัสดิ์", "ทองดี", "วงศ์ใหญ่", "มีสุข", "พึ่งบุญ", "ศรีวงศ์",
    "รุ่งเรือง", "สายทอง", "จันทร์เพ็ญ", "ประเสริฐศรี", "นาคสวัสดิ์", "แสงทอง", "เพชรรัตน์", "บุญยืน", "ธนากร", "อินทร์แก้ว",
    "พรหมมา", "คำแก้ว", "ชัยมงคล", "สมบูรณ์", "วัฒนา", "ศรีประเสริฐ", "ทองคำ", "บัวขาว", "เจริญผล", "สุวรรณ",
]

PAYMENT_METHODS = ["qr_code", "mobile_banking", "credit_card", "cash"]
PAYMENT_WEIGHTS = [45, 30, 15, 10]

GROUP_SIZES = [1, 2, 3, 4]
GROUP_WEIGHTS = [65, 22, 8, 5]


# ---------------------------------------------------------------------------
# Demand model
# ---------------------------------------------------------------------------
def hour_factor(hhmm: str) -> float:
    hour = int(hhmm[:2])
    if 7 <= hour <= 9:
        return 1.6
    if 15 <= hour <= 17:
        return 1.4
    if 11 <= hour <= 14:
        return 0.8
    return 1.0


DOW_FACTOR = {0: 1.0, 1: 0.85, 2: 0.85, 3: 0.9, 4: 1.3, 5: 1.1, 6: 1.3}  # Mon=0


def holiday_factor(day: date, origin: int, destination: int) -> float:
    """Simplified holiday calendar with direction-aware rushes."""
    leaving_bkk = origin == BANGKOK
    returning_bkk = destination == BANGKOK
    y = day.year
    # Songkran (13-15 Apr): leave Bangkok before, come back after
    if date(y, 4, 10) <= day <= date(y, 4, 12):
        return 3.0 if leaving_bkk else 0.8
    if date(y, 4, 13) <= day <= date(y, 4, 14):
        return 0.6
    if date(y, 4, 15) <= day <= date(y, 4, 17):
        return 3.0 if returning_bkk else 0.8
    # New Year: return rush into Bangkok
    if day == date(y, 1, 1):
        return 1.5 if returning_bkk else 0.7
    if date(y, 1, 2) <= day <= date(y, 1, 4):
        return 2.0 if returning_bkk else 0.9
    return 1.0


def poisson(lam: float, rng: random.Random) -> int:
    if lam <= 0:
        return 0
    if lam > 30:  # normal approximation is plenty for large means
        return max(0, round(rng.normalvariate(lam, math.sqrt(lam))))
    limit, k, p = math.exp(-lam), 0, 1.0
    while True:
        p *= rng.random()
        if p <= limit:
            return k
        k += 1


# ---------------------------------------------------------------------------
# Generated rows
# ---------------------------------------------------------------------------
@dataclass
class Schedule:
    schedule_id: int
    train_id: int
    origin: int
    destination: int
    departure: datetime
    arrival: datetime
    price: int
    weight: float


@dataclass
class Booking:
    user_id: int
    schedule: Schedule
    booked_at: datetime
    status: str
    passengers: list[str]
    seats: list[str] = field(default_factory=list)
    booking_id: int = 0


def iso(ts: datetime) -> str:
    return ts.isoformat(sep=" ", timespec="seconds")


def seat_label(n: int) -> str:
    """Seat 1..N -> car/seat label, 50 seats per car: C01-01 .. C11-50."""
    return f"C{(n - 1) // 50 + 1:02d}-{(n - 1) % 50 + 1:02d}"


def thai_name(rng: random.Random) -> str:
    return f"{rng.choice(FIRST_NAMES)} {rng.choice(LAST_NAMES)}"


# ---------------------------------------------------------------------------
# Generators
# ---------------------------------------------------------------------------
def make_users(n: int, start: date, rng: random.Random):
    """Users sorted by sign-up time. Returns rows + data for weighted picking."""
    data_start = datetime.combine(start, datetime.min.time(), BKK)
    early = data_start - timedelta(days=365)
    late_end = data_start + timedelta(days=170)

    created = []
    for _ in range(n):
        if rng.random() < 0.7:   # most signed up in the year before the data window
            ts = early + timedelta(seconds=rng.uniform(0, (data_start - early).total_seconds()))
        else:                    # the rest trickle in during the window
            ts = data_start + timedelta(seconds=rng.uniform(0, (late_end - data_start).total_seconds()))
        created.append(ts.replace(microsecond=0))
    created.sort()

    rows, weights = [], []
    for i, ts in enumerate(created, start=1):
        rows.append({
            "user_id": i,
            "username": f"user{i:05d}",
            "full_name": thai_name(rng),
            "email": f"user{i:05d}@example.com",
            "phone": f"0{rng.choice('689')}{rng.randint(10_000_000, 99_999_999)}",
            "created_at": iso(ts),
        })
        weights.append(rng.paretovariate(1.5))  # a few heavy travellers

    cum, total = [], 0.0
    for w in weights:
        total += w
        cum.append(total)
    return rows, created, cum


def make_schedules(start: date, days: int) -> list[Schedule]:
    schedules, sid = [], 0
    for d in range(days):
        day = start + timedelta(days=d)
        for train_id, origin, dest, hhmm, minutes, price in TIMETABLE:
            sid += 1
            h, m = map(int, hhmm.split(":"))
            dep = datetime(day.year, day.month, day.day, h, m, tzinfo=BKK)
            weight = (
                hour_factor(hhmm)
                * DOW_FACTOR[day.weekday()]
                * holiday_factor(day, origin, dest)
                * (1.2 if TRAIN_TYPE[train_id] == "FAN" else 1.0)
            )
            schedules.append(Schedule(sid, train_id, origin, dest, dep,
                                      dep + timedelta(minutes=minutes), price, weight))
    return schedules


def lead_time(surge: bool, rng: random.Random) -> timedelta:
    r = rng.random()
    if surge and r < 0.5:                      # holiday trips planned ahead
        hours = rng.uniform(7 * 24, 30 * 24)
    elif r < 0.35:                             # same day
        hours = rng.uniform(0.5, 12)
    elif r < 0.80:                             # within a week
        hours = rng.uniform(12, 7 * 24)
    else:                                      # long tail, up to 60 days
        hours = 7 * 24 + rng.expovariate(1 / (14 * 24))
        if hours > 60 * 24:                    # resample instead of clipping (no spike at 60d)
            hours = rng.uniform(30 * 24, 60 * 24)
    return timedelta(hours=hours)


def simulate(schedules, user_created, user_cum, target_bookings, rng):
    total_weight = sum(s.weight for s in schedules)
    stats = Counter()
    bookings: list[Booking] = []

    for s in schedules:
        lam = target_bookings * s.weight / total_weight
        surge = s.weight >= 2.0

        # 1) booking requests for this departure
        requests = []
        for _ in range(poisson(lam, rng)):
            booked_at = (s.departure - lead_time(surge, rng)).replace(microsecond=0)
            k = bisect.bisect_right(user_created, booked_at)   # users who existed then
            if k == 0:
                stats["skipped_no_user"] += 1
                continue
            user_idx = bisect.bisect_left(user_cum, rng.random() * user_cum[k - 1])
            requests.append((booked_at, user_idx + 1))
        requests.sort()

        # 2) sell seats in the order people booked
        capacity = TRAIN_CAPACITY[s.train_id]
        next_seat, free_seats, active = 1, [], 0
        for booked_at, user_id in requests:
            size = rng.choices(GROUP_SIZES, GROUP_WEIGHTS)[0]
            if active + size > capacity:
                stats["turned_away_sold_out"] += 1
                stats["turned_away_seats"] += size
                continue

            seats = []
            for _ in range(size):
                if free_seats:
                    seats.append(free_seats.pop())
                else:
                    seats.append(seat_label(next_seat))
                    next_seat += 1

            lead_days = (s.departure - booked_at).total_seconds() / 86400
            r = rng.random()
            cancel_p = 0.05 + (0.08 if lead_days > 7 else 0.0)
            if r < cancel_p:
                status = "cancelled"
                free_seats.extend(seats)          # seats go back on sale
            elif r < cancel_p + 0.04:
                status = "pending"                # abandoned / never paid, seat held
                active += size
            else:
                status = "confirmed"
                active += size

            passengers = [None] + [thai_name(rng) for _ in range(size - 1)]
            bookings.append(Booking(user_id, s, booked_at, status, passengers, seats))
            stats[status] += 1
    return bookings, stats


def make_payments(bookings, rng):
    rows, pid = [], 0

    def add(b, amount, status, at):
        nonlocal pid
        pid += 1
        rows.append({
            "payment_id": pid,
            "booking_id": b.booking_id,
            "amount": amount,
            "payment_method": rng.choices(PAYMENT_METHODS, PAYMENT_WEIGHTS)[0],
            "status": status,
            "paid_at": iso(at),
        })

    for b in bookings:
        amount = b.schedule.price * len(b.seats)
        t = b.booked_at + timedelta(minutes=rng.uniform(1, 10))
        if b.status == "confirmed":
            if rng.random() < 0.03:               # first attempt failed, retried
                add(b, amount, "failed", t)
                t += timedelta(minutes=rng.uniform(1, 15))
            add(b, amount, "paid", t)
        elif b.status == "cancelled":
            if rng.random() < 0.7:
                add(b, amount, "refunded", t)     # paid, then refunded on cancel
            elif rng.random() < 0.5:
                add(b, amount, "failed", t)
        else:  # pending
            if rng.random() < 0.3:
                add(b, amount, "failed", t)
    return rows


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def write_csv(path: Path, rows: list[dict]):
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--bookings", type=int, default=100_000, help="target number of booking requests")
    p.add_argument("--users", type=int, default=8_000)
    p.add_argument("--start", type=date.fromisoformat, default=date(2026, 1, 1))
    p.add_argument("--days", type=int, default=181, help="181 days = Jan-Jun 2026")
    p.add_argument("--seed", type=int, default=42, help="same seed -> same data")
    p.add_argument("--out", type=Path, default=Path("data/generated"))
    args = p.parse_args()

    rng = random.Random(args.seed)
    args.out.mkdir(parents=True, exist_ok=True)

    users, user_created, user_cum = make_users(args.users, args.start, rng)
    schedules = make_schedules(args.start, args.days)
    bookings, stats = simulate(schedules, user_created, user_cum, args.bookings, rng)

    # booking ids follow booking time, like a real system
    bookings.sort(key=lambda b: (b.booked_at, b.schedule.schedule_id))
    for i, b in enumerate(bookings, start=1):
        b.booking_id = i

    user_names = {u["user_id"]: u["full_name"] for u in users}
    tickets, tid = [], 0
    for b in bookings:
        for seat, name in zip(b.seats, b.passengers):
            tid += 1
            tickets.append({
                "ticket_id": tid,
                "booking_id": b.booking_id,
                "schedule_id": b.schedule.schedule_id,
                "seat_number": seat,
                "passenger_name": name or user_names[b.user_id],
                "is_active": "false" if b.status == "cancelled" else "true",
            })

    payments = make_payments(bookings, rng)

    write_csv(args.out / "users.csv", users)
    write_csv(args.out / "schedules.csv", [{
        "schedule_id": s.schedule_id,
        "train_id": s.train_id,
        "origin_station_id": s.origin,
        "destination_station_id": s.destination,
        "departure_time": iso(s.departure),
        "arrival_time": iso(s.arrival),
        "price": s.price,
    } for s in schedules])
    write_csv(args.out / "bookings.csv", [{
        "booking_id": b.booking_id,
        "user_id": b.user_id,
        "schedule_id": b.schedule.schedule_id,
        "status": b.status,
        "booked_at": iso(b.booked_at),
    } for b in bookings])
    write_csv(args.out / "tickets.csv", tickets)
    write_csv(args.out / "payments.csv", payments)

    print(f"wrote CSVs to {args.out}/")
    print(f"  users      {len(users):>8,}")
    print(f"  schedules  {len(schedules):>8,}")
    print(f"  bookings   {len(bookings):>8,}  "
          f"(confirmed {stats['confirmed']:,} / pending {stats['pending']:,} / cancelled {stats['cancelled']:,})")
    print(f"  tickets    {len(tickets):>8,}")
    print(f"  payments   {len(payments):>8,}")
    print(f"  turned away (sold out): {stats['turned_away_sold_out']:,} bookings, "
          f"{stats['turned_away_seats']:,} seats")


if __name__ == "__main__":
    main()
