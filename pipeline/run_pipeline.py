import argparse
import logging
import os
import re
import sys
import time
from datetime import date
from pathlib import Path

import pyodbc

ROOT = Path(__file__).resolve().parent.parent
EVENT_FILE = re.compile(r"^events_(\d{4}-\d{2}-\d{2})\.csv$")

log = logging.getLogger("pipeline")


def read_env(path: Path) -> dict[str, str]:
    values = {}
    if path.exists():
        for line in path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, value = line.split("=", 1)
                values[key.strip()] = value.strip()
    return values


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the container D&D pipeline end to end.")
    parser.add_argument("--server", default="localhost,1433")
    parser.add_argument("--database", default="dd_warehouse")
    parser.add_argument("--events-dir", type=Path, default=ROOT / "data" / "events")
    parser.add_argument("--until", type=date.fromisoformat, default=None,
                        help="Only load event files dated on or before this day (YYYY-MM-DD)")
    return parser.parse_args()


def connect(args: argparse.Namespace) -> pyodbc.Connection:
    password = os.environ.get("MSSQL_SA_PASSWORD") or read_env(ROOT / ".env").get("MSSQL_SA_PASSWORD")
    if not password:
        raise SystemExit("MSSQL_SA_PASSWORD not found in the environment or in .env")
    conn = pyodbc.connect(
        "DRIVER={ODBC Driver 18 for SQL Server};"
        f"SERVER={args.server};DATABASE={args.database};UID=sa;PWD={password};"
        "Encrypt=yes;TrustServerCertificate=yes",
        autocommit=True,
        timeout=15,
    )
    conn.timeout = 0
    return conn


def execute(cur: pyodbc.Cursor, sql: str, *params) -> None:
    cur.execute(sql, *params)
    while cur.nextset():
        pass


def scalar(cur: pyodbc.Cursor, sql: str):
    return cur.execute(sql).fetchone()[0]


def event_files(events_dir: Path, until: date | None) -> list[Path]:
    files = []
    for path in sorted(events_dir.glob("events_*.csv")):
        match = EVENT_FILE.match(path.name)
        if not match:
            log.warning("skipped unexpected file name: %s", path.name)
            continue
        if until is None or date.fromisoformat(match.group(1)) <= until:
            files.append(path)
    return files


def print_summary(cur: pyodbc.Cursor, first_run_id: int) -> None:
    rows = cur.execute(
        """
        SELECT CASE WHEN step_name LIKE N'raw.load_reference_file:%' THEN N'raw.load_reference_file'
                    ELSE step_name END AS step,
               COUNT(*) AS runs,
               SUM(ISNULL(rows_read, 0)) AS rows_read,
               SUM(ISNULL(rows_inserted, 0)) AS rows_inserted,
               SUM(ISNULL(rows_rejected, 0)) AS rows_rejected,
               SUM(DATEDIFF(SECOND, start_ts, end_ts)) AS seconds,
               MIN(status) AS status
        FROM etl.run_log
        WHERE run_id > ?
        GROUP BY CASE WHEN step_name LIKE N'raw.load_reference_file:%' THEN N'raw.load_reference_file'
                      ELSE step_name END
        ORDER BY MIN(run_id)
        """,
        first_run_id,
    ).fetchall()
    log.info("%-32s %5s %10s %10s %9s %7s  %s", "step", "runs", "read", "inserted", "rejected", "sec", "status")
    for r in rows:
        log.info("%-32s %5d %10d %10d %9d %7d  %s", r.step, r.runs, r.rows_read, r.rows_inserted,
                 r.rows_rejected, r.seconds or 0, r.status)

    dq = cur.execute(
        """
        SELECT severity,
               SUM(CASE WHEN status = N'pass' THEN 1 ELSE 0 END) AS passed,
               SUM(CASE WHEN status = N'fail' THEN 1 ELSE 0 END) AS failed
        FROM dq.check_result
        WHERE dq_run_id = (SELECT MAX(dq_run_id) FROM dq.check_result)
        GROUP BY severity
        """
    ).fetchall()
    for r in dq:
        log.info("data quality %-7s checks: %d passed, %d failed", r.severity, r.passed, r.failed)


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s", datefmt="%H:%M:%S")
    args = parse_args()
    started = time.perf_counter()

    files = event_files(args.events_dir, args.until)
    if not files:
        log.error("no event files found in %s", args.events_dir)
        return 1

    with connect(args) as conn:
        cur = conn.cursor()
        first_run_id = scalar(cur, "SELECT ISNULL(MAX(run_id), 0) FROM etl.run_log")
        manifest_before = scalar(cur, "SELECT COUNT(*) FROM etl.file_manifest")

        log.info("loading reference files")
        execute(cur, "EXEC raw.load_all_reference_files")

        log.info("loading %d event files (already-loaded files are skipped)", len(files))
        for path in files:
            execute(cur, "EXEC raw.load_event_file @file_name = ?", path.name)
        manifest_after = scalar(cur, "SELECT COUNT(*) FROM etl.file_manifest")
        log.info("new event files loaded: %d", manifest_after - manifest_before)

        log.info("running transformations: staging, dimensions, fact, data quality, D&D charges")
        execute(cur, "EXEC etl.run_transform")

        print_summary(cur, first_run_id)

    log.info("pipeline finished in %.1f s", time.perf_counter() - started)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except pyodbc.Error as exc:
        log.error("pipeline failed: %s", exc)
        sys.exit(1)
