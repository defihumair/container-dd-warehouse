import os
from pathlib import Path

import pyodbc

ROOT = Path(__file__).resolve().parent.parent


def password() -> str:
    value = os.environ.get("MSSQL_SA_PASSWORD")
    if value:
        return value
    env_file = ROOT / ".env"
    if env_file.exists():
        for line in env_file.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line.startswith("MSSQL_SA_PASSWORD="):
                return line.split("=", 1)[1].strip()
    raise RuntimeError("MSSQL_SA_PASSWORD not found in the environment or in .env")


def connect(autocommit: bool = False) -> pyodbc.Connection:
    server = os.environ.get("DD_SQL_SERVER", "localhost,1433")
    conn = pyodbc.connect(
        "DRIVER={ODBC Driver 18 for SQL Server};"
        f"SERVER={server};DATABASE=dd_warehouse;UID=sa;PWD={password()};"
        "Encrypt=yes;TrustServerCertificate=yes",
        autocommit=autocommit,
        timeout=15,
    )
    conn.timeout = 0
    return conn


def run(cur: pyodbc.Cursor, sql: str, *params) -> None:
    cur.execute(sql, *params)
    while cur.nextset():
        pass


def scalar(cur: pyodbc.Cursor, sql: str, *params):
    row = cur.execute(sql, *params).fetchone()
    return None if row is None else row[0]
