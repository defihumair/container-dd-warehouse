import argparse
import csv
import json
import shutil
from collections import defaultdict
from datetime import date, datetime, timedelta
from pathlib import Path

import numpy as np

PORTS = [
    ("PKKHI", "Karachi", "PK", 3.0),
    ("PKBQM", "Port Qasim", "PK", 2.0),
    ("AEJEA", "Jebel Ali", "AE", 3.0),
    ("SAJED", "Jeddah", "SA", 1.5),
    ("OMSLL", "Salalah", "OM", 1.0),
    ("INNSA", "Nhava Sheva", "IN", 2.0),
    ("LKCMB", "Colombo", "LK", 1.5),
    ("SGSIN", "Singapore", "SG", 3.0),
    ("CNSHA", "Shanghai", "CN", 3.0),
    ("CNNGB", "Ningbo", "CN", 2.0),
    ("MYPKG", "Port Klang", "MY", 1.5),
    ("NLRTM", "Rotterdam", "NL", 2.0),
    ("DEHAM", "Hamburg", "DE", 1.5),
    ("BEANR", "Antwerp", "BE", 1.5),
    ("EGPSD", "Port Said", "EG", 1.0),
]
PORT_POSITION = {
    "NLRTM": 0, "DEHAM": 0, "BEANR": 0, "EGPSD": 9, "SAJED": 11, "OMSLL": 13,
    "AEJEA": 14, "PKKHI": 15, "PKBQM": 15, "INNSA": 16, "LKCMB": 18,
    "MYPKG": 21, "SGSIN": 21, "CNNGB": 26, "CNSHA": 26,
}
CONTAINER_TYPES = ["20DC", "40DC", "40HC", "40RF"]
CONTAINER_TYPE_WEIGHTS = [0.35, 0.20, 0.35, 0.10]
OWNER_CODES = ["DDX", "QZT", "VXL", "KRB", "LNW"]
NAME_PREFIXES = [
    "Indus", "Crescent", "Harbor", "Summit", "Delta", "Falcon", "Orion", "Pioneer",
    "Zenith", "Atlas", "Meridian", "Nova", "Sapphire", "Cedar", "Horizon", "Lotus",
    "Apex", "Coastal", "Silverline", "Greenfield",
]
SEGMENTS = ["Textiles", "Foods", "Chemicals", "Electronics", "Retail", "Pharma", "Auto Parts"]
LEGAL_FORMS = ["Ltd", "Pvt Ltd", "Trading Co", "Industries"]
VESSEL_WORDS = [
    "Aurora", "Borealis", "Cascade", "Dune", "Ember", "Fjord", "Glacier", "Halcyon",
    "Iris", "Juniper", "Kestrel", "Lumen", "Monsoon", "Nimbus", "Opal", "Polaris",
    "Quasar", "Radiant", "Sirocco", "Tidewater", "Umbra", "Vega", "Willow", "Xenia",
    "Yonder", "Zephyr", "Albatross", "Beacon", "Corsair", "Drift",
]
TARIFF_TIERS = [
    ("DEMURRAGE", "20DC", 1, 5, 0), ("DEMURRAGE", "20DC", 6, 10, 40), ("DEMURRAGE", "20DC", 11, None, 80),
    ("DEMURRAGE", "40DC", 1, 5, 0), ("DEMURRAGE", "40DC", 6, 10, 60), ("DEMURRAGE", "40DC", 11, None, 120),
    ("DEMURRAGE", "40HC", 1, 5, 0), ("DEMURRAGE", "40HC", 6, 10, 70), ("DEMURRAGE", "40HC", 11, None, 140),
    ("DEMURRAGE", "40RF", 1, 5, 0), ("DEMURRAGE", "40RF", 6, 10, 120), ("DEMURRAGE", "40RF", 11, None, 240),
    ("DETENTION", "20DC", 1, 7, 0), ("DETENTION", "20DC", 8, 14, 30), ("DETENTION", "20DC", 15, None, 60),
    ("DETENTION", "40DC", 1, 7, 0), ("DETENTION", "40DC", 8, 14, 45), ("DETENTION", "40DC", 15, None, 90),
    ("DETENTION", "40HC", 1, 7, 0), ("DETENTION", "40HC", 8, 14, 50), ("DETENTION", "40HC", 15, None, 100),
    ("DETENTION", "40RF", 1, 7, 0), ("DETENTION", "40RF", 8, 14, 100), ("DETENTION", "40RF", 15, None, 200),
]
MONTH_DWELL_FACTOR = {1: 1.0, 2: 1.0, 3: 1.25, 4: 1.25, 5: 1.0, 6: 1.0, 7: 1.1, 8: 1.1, 9: 1.0, 10: 1.2, 11: 1.3, 12: 1.3}
ERROR_RATES = {
    "duplicate_event": 0.010,
    "missing_gtin": 0.005,
    "out_of_order": 0.003,
    "unknown_port": 0.003,
    "bad_check_digit": 0.003,
    "invalid_timestamp": 0.001,
}
LATE_ARRIVAL_RATE = 0.02
SCD2_CHANGE_RATE = 0.02
CHRONIC_CUSTOMERS = 10
TS_FORMAT = "%Y-%m-%d %H:%M:%S"


def iso6346_check_digit(code10: str) -> int:
    values, v = {}, 10
    for ch in "ABCDEFGHIJKLMNOPQRSTUVWXYZ":
        if v % 11 == 0:
            v += 1
        values[ch] = v
        v += 1
    total = sum((values[c] if c.isalpha() else int(c)) * 2 ** i for i, c in enumerate(code10))
    return total % 11 % 10


def imo_number(six_digits: str) -> str:
    check = sum(int(d) * w for d, w in zip(six_digits, range(7, 1, -1))) % 10
    return f"{six_digits}{check}"


def parse_args() -> argparse.Namespace:
    default_out = Path(__file__).resolve().parent.parent / "data"
    parser = argparse.ArgumentParser(description="Generate synthetic container event data.")
    parser.add_argument("--start", type=date.fromisoformat, default=date(2026, 1, 1))
    parser.add_argument("--days", type=int, default=180)
    parser.add_argument("--containers", type=int, default=50000)
    parser.add_argument("--customers", type=int, default=200)
    parser.add_argument("--vessels", type=int, default=30)
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--out", type=Path, default=default_out)
    args = parser.parse_args()
    if args.days < 30:
        parser.error("--days must be at least 30")
    if args.customers < CHRONIC_CUSTOMERS * 2:
        parser.error(f"--customers must be at least {CHRONIC_CUSTOMERS * 2}")
    return args


def write_csv(path: Path, header: list[str], rows: list) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(header)
        writer.writerows(rows)


def build_customers(rng: np.random.Generator, n: int) -> tuple[list, np.ndarray, set]:
    combos = [(p, s, l) for p in NAME_PREFIXES for s in SEGMENTS for l in LEGAL_FORMS]
    picks = rng.choice(len(combos), size=n, replace=n > len(combos))
    rows, seen = [], defaultdict(int)
    for i, idx in enumerate(picks, start=1):
        prefix, segment, legal = combos[idx]
        name = f"{prefix} {segment} {legal}"
        seen[name] += 1
        if seen[name] > 1:
            name = f"{name} {seen[name]}"
        rows.append((f"CUST{i:04d}", name, segment))
    weights = 1.0 / np.arange(1, n + 1) ** 0.8
    weights = rng.permutation(weights)
    weights /= weights.sum()
    chronic = set(rng.choice([r[0] for r in rows], size=CHRONIC_CUSTOMERS, replace=False).tolist())
    return rows, weights, chronic


def build_vessels(rng: np.random.Generator, n: int) -> list:
    rows = []
    for i in range(1, n + 1):
        word = VESSEL_WORDS[(i - 1) % len(VESSEL_WORDS)]
        suffix = "" if i <= len(VESSEL_WORDS) else f" {i // len(VESSEL_WORDS) + 1}"
        six = f"{rng.integers(100000, 999999)}"
        rows.append((f"VSL{i:03d}", f"MV {word}{suffix}", imo_number(six)))
    return rows


def build_containers(rng: np.random.Generator, n: int, start: date) -> list:
    serials = rng.choice(1_000_000, size=n, replace=False)
    types = rng.choice(CONTAINER_TYPES, size=n, p=CONTAINER_TYPE_WEIGHTS)
    owners = rng.choice(["OWN", "LEASED"], size=n, p=[0.7, 0.3])
    initial_date = start - timedelta(days=365)
    rows = []
    for i in range(n):
        owner_code = OWNER_CODES[i % len(OWNER_CODES)]
        code10 = f"{owner_code}U{serials[i]:06d}"
        rows.append((f"{code10}{iso6346_check_digit(code10)}", str(types[i]), str(owners[i]), initial_date.isoformat()))
    return rows


def build_lanes(rng: np.random.Generator, n_vessels: int) -> dict:
    lanes = {}
    codes = [p[0] for p in PORTS]
    for o in codes:
        for d in codes:
            if o == d:
                continue
            distance = abs(PORT_POSITION[o] - PORT_POSITION[d])
            transit = max(2, int(round(2 + distance * 0.9 + rng.normal(0, 1.0))))
            lanes[(o, d)] = {
                "transit": transit,
                "weekday": int(rng.integers(0, 7)),
                "vessel": f"VSL{int(rng.integers(1, n_vessels + 1)):03d}",
            }
    return lanes


def next_sailing(after: datetime, weekday: int) -> datetime:
    days_ahead = (weekday - after.weekday()) % 7
    if days_ahead == 0 and after.hour >= 12:
        days_ahead = 7
    sail_day = (after + timedelta(days=days_ahead)).date()
    return datetime.combine(sail_day, datetime.min.time()) + timedelta(hours=18)


def gate_time(rng: np.random.Generator, day: datetime) -> datetime:
    base = datetime.combine(day.date(), datetime.min.time())
    return base + timedelta(hours=float(rng.uniform(6, 22)))


def simulate(args: argparse.Namespace, rng: np.random.Generator, containers: list, customers: list,
             customer_weights: np.ndarray, chronic: set, lanes: dict) -> tuple[list, list, dict]:
    start_dt = datetime.combine(args.start, datetime.min.time())
    end_dt = start_dt + timedelta(days=args.days)
    port_codes = [p[0] for p in PORTS]
    port_weights = np.array([p[3] for p in PORTS])
    customer_ids = [c[0] for c in customers]
    events, shipments, voyages = [], [], {}
    booking_seq = 0
    for container_no, _, _, _ in containers:
        port = port_codes[rng.choice(len(port_codes), p=port_weights / port_weights.sum())]
        ready = start_dt + timedelta(days=float(rng.uniform(0, 30)))
        while ready < end_dt:
            mask = np.array([c != port for c in port_codes])
            w = port_weights * mask
            dest = port_codes[rng.choice(len(port_codes), p=w / w.sum())]
            lane = lanes[(port, dest)]
            departure = next_sailing(ready, lane["weekday"])
            arrival = departure + timedelta(days=lane["transit"], hours=float(rng.uniform(-6, 18)))
            voyage_no = f"{lane['vessel']}-{departure:%y%m%d}-{port[2:]}{dest[2:]}"
            voyages[voyage_no] = (voyage_no, lane["vessel"], port, dest, departure, arrival)
            booking_seq += 1
            booking_ref = f"BK{booking_seq:08d}"
            customer = customer_ids[rng.choice(len(customer_ids), p=customer_weights)]
            shipments.append((booking_ref, customer, container_no, voyage_no, port, dest))
            load_ts = departure - timedelta(hours=float(rng.uniform(2, 30)))
            disc_ts = arrival + timedelta(hours=float(rng.uniform(4, 36)))
            factor = MONTH_DWELL_FACTOR[disc_ts.month]
            dem_days = rng.lognormal(np.log(3.5 * factor), 0.55)
            gtot_ts = gate_time(rng, disc_ts + timedelta(days=float(dem_days)))
            if gtot_ts <= disc_ts:
                gtot_ts = disc_ts + timedelta(hours=float(rng.uniform(6, 20)))
            det_mean = 6.0 * factor * (2.2 if customer in chronic else 1.0)
            det_days = rng.lognormal(np.log(det_mean), 0.5)
            gtin_ts = gate_time(rng, gtot_ts + timedelta(days=float(det_days)))
            if gtin_ts <= gtot_ts:
                gtin_ts = gtot_ts + timedelta(hours=float(rng.uniform(6, 20)))
            for event_type, ts, at_port in (("LOAD", load_ts, port), ("DISC", disc_ts, dest),
                                            ("GTOT", gtot_ts, dest), ("GTIN", gtin_ts, dest)):
                if ts < end_dt:
                    events.append({"container_no": container_no, "event_type": event_type, "event_ts": ts,
                                   "port_code": at_port, "booking_ref": booking_ref, "voyage_no": voyage_no})
            port = dest
            ready = gtin_ts + timedelta(days=float(rng.uniform(1, 10)))
    return events, shipments, voyages


def inject_errors(rng: np.random.Generator, events: list, end_dt: datetime) -> tuple[list, list]:
    manifest = []
    by_booking = defaultdict(dict)
    for e in events:
        by_booking[e["booking_ref"]][e["event_type"]] = e
    complete = [b for b, ev in by_booking.items() if {"DISC", "GTOT", "GTIN"} <= ev.keys()]
    rng.shuffle(complete)
    n_missing = int(len(complete) * ERROR_RATES["missing_gtin"])
    n_order = int(len(complete) * ERROR_RATES["out_of_order"])
    dropped = set()
    for b in complete[:n_missing]:
        e = by_booking[b]["GTIN"]
        dropped.add(id(e))
        manifest.append((e["event_id"], "missing_gtin"))
    for b in complete[n_missing:n_missing + n_order]:
        disc, gtot = by_booking[b]["DISC"], by_booking[b]["GTOT"]
        gtot["event_ts"] = disc["event_ts"] - timedelta(days=1, hours=float(rng.uniform(1, 12)))
        manifest.append((gtot["event_id"], "out_of_order"))
    kept = [e for e in events if id(e) not in dropped]
    n = len(kept)
    for error_type in ("unknown_port", "bad_check_digit", "invalid_timestamp"):
        for idx in rng.choice(n, size=int(n * ERROR_RATES[error_type]), replace=False):
            e = kept[idx]
            if e.get("error"):
                continue
            e["error"] = error_type
            if error_type == "unknown_port":
                e["port_code"] = str(rng.choice(["PKXXX", "ZZZZZ", "AEJEB"]))
            elif error_type == "bad_check_digit":
                cn = e["container_no"]
                e["container_no"] = f"{cn[:-1]}{(int(cn[-1]) + 1) % 10}"
            else:
                e["raw_ts"] = "2026-02-30 25:61:00"
            manifest.append((e["event_id"], error_type))
    duplicates = []
    for idx in rng.choice(n, size=int(n * ERROR_RATES["duplicate_event"]), replace=False):
        dup = dict(kept[idx])
        dup["file_shift"] = int(rng.integers(0, 2))
        duplicates.append(dup)
        manifest.append((dup["event_id"], "duplicate_event"))
    return kept + duplicates, manifest


def assign_files(rng: np.random.Generator, events: list, start: date, end: date) -> dict:
    files = defaultdict(list)
    late = 0
    for e in events:
        file_day = e["event_ts"].date() if "raw_ts" not in e else e["event_ts"].date()
        file_day = max(file_day, start)
        if rng.random() < LATE_ARRIVAL_RATE:
            file_day += timedelta(days=int(rng.integers(1, 4)))
            e["late"] = True
            late += 1
        file_day += timedelta(days=e.get("file_shift", 0))
        if file_day < end:
            files[file_day].append(e)
    return files


def main() -> None:
    args = parse_args()
    rng = np.random.default_rng(args.seed)
    end = args.start + timedelta(days=args.days)
    end_dt = datetime.combine(end, datetime.min.time())
    out = args.out
    for sub in ("ref", "events", "_validation"):
        shutil.rmtree(out / sub, ignore_errors=True)

    customers, customer_weights, chronic = build_customers(rng, args.customers)
    vessels = build_vessels(rng, args.vessels)
    containers = build_containers(rng, args.containers, args.start)
    lanes = build_lanes(rng, args.vessels)

    events, shipments, voyages = simulate(args, rng, containers, customers, customer_weights, chronic, lanes)
    events.sort(key=lambda e: (e["event_ts"], e["container_no"]))
    for i, e in enumerate(events, start=1):
        e["event_id"] = f"EV{i:09d}"

    changes = []
    change_window = (args.start + timedelta(days=30), end - timedelta(days=30))
    span = (change_window[1] - change_window[0]).days
    for idx in rng.choice(len(containers), size=int(len(containers) * SCD2_CHANGE_RATE), replace=False):
        container_no, ctype, owner, _ = containers[idx]
        new_owner = "OWN" if owner == "LEASED" else "LEASED"
        eff = change_window[0] + timedelta(days=int(rng.integers(0, span + 1)))
        changes.append((container_no, ctype, new_owner, eff.isoformat()))

    events, manifest = inject_errors(rng, events, end_dt)
    files = assign_files(rng, events, args.start, end)

    write_csv(out / "ref" / "ports.csv", ["port_code", "port_name", "country"], [p[:3] for p in PORTS])
    write_csv(out / "ref" / "customers.csv", ["customer_id", "customer_name", "segment"], customers)
    write_csv(out / "ref" / "vessels.csv", ["vessel_id", "vessel_name", "imo_no"], vessels)
    write_csv(out / "ref" / "containers.csv", ["container_no", "container_type", "owner_type", "effective_date"], containers)
    write_csv(out / "ref" / "container_changes.csv", ["container_no", "container_type", "owner_type", "effective_date"], changes)
    write_csv(out / "ref" / "voyages.csv",
              ["voyage_no", "vessel_id", "origin_port", "destination_port", "departure_ts", "arrival_ts"],
              [(v[0], v[1], v[2], v[3], v[4].strftime(TS_FORMAT), v[5].strftime(TS_FORMAT)) for v in voyages.values()])
    write_csv(out / "ref" / "shipments.csv",
              ["booking_ref", "customer_id", "container_no", "voyage_no", "origin_port", "destination_port"], shipments)
    write_csv(out / "ref" / "tariff_tiers.csv", ["charge_type", "container_type", "from_day", "to_day", "rate_usd"],
              [(c, t, f, "" if to is None else to, r) for c, t, f, to, r in TARIFF_TIERS])

    header = ["event_id", "container_no", "event_type", "event_ts", "port_code", "booking_ref", "voyage_no"]
    total_rows = 0
    for day in (args.start + timedelta(days=i) for i in range(args.days)):
        rows = [(e["event_id"], e["container_no"], e["event_type"], e.get("raw_ts", e["event_ts"].strftime(TS_FORMAT)),
                 e["port_code"], e["booking_ref"], e["voyage_no"]) for e in files.get(day, [])]
        write_csv(out / "events" / f"events_{day.isoformat()}.csv", header, rows)
        total_rows += len(rows)

    write_csv(out / "_validation" / "errors_manifest.csv", ["event_id", "error_type"], manifest)
    write_csv(out / "_validation" / "chronic_customers.csv", ["customer_id"], [(c,) for c in sorted(chronic)])
    error_counts = defaultdict(int)
    for _, t in manifest:
        error_counts[t] += 1
    summary = {
        "seed": args.seed,
        "start": args.start.isoformat(),
        "days": args.days,
        "containers": len(containers),
        "customers": len(customers),
        "vessels": len(vessels),
        "voyages": len(voyages),
        "shipments": len(shipments),
        "scd2_changes": len(changes),
        "event_files": args.days,
        "event_rows_written": total_rows,
        "late_arriving_rows": sum(1 for d in files.values() for e in d if e.get("late")),
        "injected_errors": dict(error_counts),
    }
    (out / "_validation" / "summary.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
