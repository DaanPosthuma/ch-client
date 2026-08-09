import datetime

import pytest
from clickhouse_connect.driver.exceptions import DatabaseError


def test_ping(client):
    assert client.ping()


def test_select_literal(client):
    result = client.query("SELECT 1 + 1 AS answer")
    assert result.result_rows == [(2,)]


def test_version_matches_built_binary(client):
    (version,) = client.query("SELECT version()").result_rows[0]
    assert version.startswith("26.8.1")


def test_now_returns_datetime(client):
    (now,) = client.query("SELECT now()").result_rows[0]
    assert isinstance(now, datetime.datetime)


def test_create_insert_select_roundtrip(client, temp_table):
    client.command(
        f"CREATE TABLE {temp_table} (id UInt32, name String) ENGINE = MergeTree ORDER BY id"
    )
    client.insert(
        temp_table,
        [[1, "alice"], [2, "bob"], [3, "carol"]],
        column_names=["id", "name"],
    )
    result = client.query(f"SELECT id, name FROM {temp_table} ORDER BY id")
    assert result.result_rows == [(1, "alice"), (2, "bob"), (3, "carol")]


def test_aggregate_query(client, temp_table):
    client.command(
        f"CREATE TABLE {temp_table} (n UInt32) ENGINE = MergeTree ORDER BY n"
    )
    client.insert(temp_table, [[n] for n in range(1, 11)], column_names=["n"])
    (total, avg, count) = client.query(
        f"SELECT sum(n), avg(n), count() FROM {temp_table}"
    ).result_rows[0]
    assert total == 55
    assert avg == pytest.approx(5.5)
    assert count == 10


def test_invalid_query_raises(client):
    with pytest.raises(DatabaseError):
        client.query("SELECT * FROM this_table_does_not_exist")


def test_parameterized_query(client):
    result = client.query(
        "SELECT {x:UInt32} + {y:UInt32} AS total", parameters={"x": 10, "y": 32}
    )
    assert result.result_rows == [(42,)]
