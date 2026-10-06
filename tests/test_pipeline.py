import pytest

from db import run, scalar


@pytest.mark.parametrize(
    "container_no, expected",
    [("CSQU3054383", True), ("CSQU3054384", False), ("CSQU305438", False), (None, False)],
)
def test_container_check_digit(cur, container_no, expected):
    assert bool(scalar(cur, "SELECT dq.fn_is_valid_container_no(?)", container_no)) is expected


def test_layers_reconcile(cur):
    raw = scalar(cur, "SELECT COUNT(*) FROM raw.container_event")
    stg = scalar(cur, "SELECT COUNT(*) FROM stg.container_event")
    rejected = scalar(cur, "SELECT COUNT(*) FROM stg.rejected_event")
    fact = scalar(cur, "SELECT COUNT(*) FROM dw.fact_container_event")
    assert raw > 0
    assert raw == stg + rejected
    assert stg == fact


@pytest.mark.parametrize("procedure", ["stg.load_container_event", "dw.load_fact_container_event"])
def test_incremental_load_is_idempotent(cur, procedure):
    run(cur, f"EXEC {procedure}")
    fact_before = scalar(cur, "SELECT COUNT(*) FROM dw.fact_container_event")
    stg_before = scalar(cur, "SELECT COUNT(*) FROM stg.container_event")
    run(cur, f"EXEC {procedure}")
    assert scalar(cur, "SELECT COUNT(*) FROM dw.fact_container_event") == fact_before
    assert scalar(cur, "SELECT COUNT(*) FROM stg.container_event") == stg_before
    last_read = scalar(
        cur,
        "SELECT TOP (1) rows_read FROM etl.run_log WHERE step_name = ? ORDER BY run_id DESC",
        procedure,
    )
    assert last_read == 0


def test_scd2_keeps_history(cur):
    cur.execute(
        "INSERT INTO stg.container (container_no, container_type, owner_type, effective_date) "
        "VALUES (N'TSTU9000001', N'20DC', N'OWN', '2025-01-01')"
    )
    cur.execute(
        "INSERT INTO stg.container_change (container_no, container_type, owner_type, effective_date) "
        "VALUES (N'TSTU9000001', N'20DC', N'LEASED', '2026-02-01')"
    )
    run(cur, "EXEC dw.load_dimensions")
    rows = cur.execute(
        "SELECT owner_type, CONVERT(CHAR(10), valid_from, 23) AS valid_from, "
        "CONVERT(CHAR(10), valid_to, 23) AS valid_to, is_current "
        "FROM dw.dim_container WHERE container_no = N'TSTU9000001' ORDER BY valid_from"
    ).fetchall()
    assert len(rows) == 2
    assert (rows[0].owner_type, rows[0].valid_from, rows[0].valid_to, rows[0].is_current) == \
        ("OWN", "2025-01-01", "2026-02-01", False)
    assert (rows[1].owner_type, rows[1].valid_from, rows[1].valid_to, rows[1].is_current) == \
        ("LEASED", "2026-02-01", None, True)


def test_error_level_quality_checks_pass(cur):
    run(cur, "EXEC dq.run_checks @fail_on_error = 0")
    failed = cur.execute(
        "SELECT check_name FROM dq.check_result "
        "WHERE dq_run_id = (SELECT MAX(dq_run_id) FROM dq.check_result) "
        "AND severity = N'error' AND status = N'fail'"
    ).fetchall()
    assert [r.check_name for r in failed] == []
