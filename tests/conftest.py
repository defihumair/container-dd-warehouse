import pytest

from db import connect


@pytest.fixture(scope="session")
def conn():
    connection = connect()
    yield connection
    connection.close()


@pytest.fixture
def cur(conn):
    cursor = conn.cursor()
    yield cursor
    conn.rollback()
    cursor.close()
