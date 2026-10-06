import pytest

from db import connect, run

AS_OF = "2026-06-29"

CONTAINERS = [
    ("TSTU0000001", "20DC"),
    ("TSTU0000002", "40HC"),
    ("TSTU0000003", "40RF"),
    ("TSTU0000004", "20DC"),
    ("TSTU0000005", "20DC"),
]

EVENTS = [
    ("TSTU0000001", "TSTBK001", "DISC", "2026-03-01 10:00:00"),
    ("TSTU0000001", "TSTBK001", "GTOT", "2026-03-12 09:00:00"),
    ("TSTU0000001", "TSTBK001", "GTIN", "2026-03-15 12:00:00"),
    ("TSTU0000002", "TSTBK002", "DISC", "2026-03-01 10:00:00"),
    ("TSTU0000002", "TSTBK002", "GTOT", "2026-03-08 15:00:00"),
    ("TSTU0000002", "TSTBK002", "GTIN", "2026-03-09 11:00:00"),
    ("TSTU0000003", "TSTBK003", "DISC", "2026-03-01 10:00:00"),
    ("TSTU0000003", "TSTBK003", "GTOT", "2026-03-02 08:00:00"),
    ("TSTU0000003", "TSTBK003", "GTIN", "2026-03-21 08:00:00"),
    ("TSTU0000004", "TSTBK004", "DISC", "2026-06-20 10:00:00"),
    ("TSTU0000005", "TSTBK005", "DISC", "2026-03-10 10:00:00"),
    ("TSTU0000005", "TSTBK005", "GTOT", "2026-03-09 08:00:00"),
]


@pytest.fixture(scope="module")
def charges():
    conn = connect()
    cur = conn.cursor()
    sk = {}
    for container_no, container_type in CONTAINERS:
        cur.execute(
            "INSERT INTO dw.dim_container (container_no, container_type, owner_type, valid_from, valid_to, is_current) "
            "OUTPUT inserted.container_sk VALUES (?, ?, N'OWN', '2025-01-01', NULL, 1)",
            container_no, container_type,
        )
        sk[container_no] = cur.fetchone()[0]
    for i, (container_no, booking_ref, event_type, ts) in enumerate(EVENTS, start=1):
        cur.execute(
            "INSERT INTO dw.fact_container_event (event_id, container_sk, port_sk, customer_sk, vessel_sk, date_key, "
            "event_type, event_ts, booking_ref, voyage_no, stg_loaded_at) "
            "VALUES (?, ?, -1, -1, -1, CONVERT(INT, CONVERT(CHAR(8), CAST(? AS DATETIME2(0)), 112)), ?, "
            "CAST(? AS DATETIME2(0)), ?, NULL, SYSUTCDATETIME())",
            f"TEST{i:06d}", sk[container_no], ts, event_type, ts, booking_ref,
        )
    run(cur, "EXEC dw.load_dd_charge @as_of = ?", AS_OF)
    rows = cur.execute(
        "SELECT booking_ref, charge_type, charge_days, is_open, charge_usd "
        "FROM dw.fact_dd_charge WHERE booking_ref LIKE N'TSTBK%'"
    ).fetchall()
    yield {(r.booking_ref, r.charge_type): r for r in rows}
    conn.rollback()
    conn.close()


@pytest.mark.parametrize(
    "booking_ref, charge_type, days, usd, is_open",
    [
        ("TSTBK001", "DEMURRAGE", 12, 360, 0),
        ("TSTBK001", "DETENTION", 4, 0, 0),
        ("TSTBK002", "DEMURRAGE", 8, 210, 0),
        ("TSTBK003", "DEMURRAGE", 2, 0, 0),
        ("TSTBK003", "DETENTION", 20, 1900, 0),
        ("TSTBK004", "DEMURRAGE", 10, 200, 1),
    ],
)
def test_tiered_charge(charges, booking_ref, charge_type, days, usd, is_open):
    row = charges.get((booking_ref, charge_type))
    assert row is not None, f"no {charge_type} row for {booking_ref}"
    assert row.charge_days == days
    assert row.charge_usd == usd
    assert row.is_open == is_open


def test_open_demurrage_has_no_detention(charges):
    assert ("TSTBK004", "DETENTION") not in charges


def test_gate_out_before_discharge_is_excluded(charges):
    assert not any(key[0] == "TSTBK005" for key in charges)
