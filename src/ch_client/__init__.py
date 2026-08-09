import os

import clickhouse_connect
from clickhouse_connect.driver.client import Client

DEFAULT_HOST = os.environ.get("CH_HOST", "localhost")
DEFAULT_PORT = int(os.environ.get("CH_HTTP_PORT", "8123"))


def get_client(**overrides) -> Client:
    """Connect to the local RelWithDebInfo ClickHouse server over HTTP."""
    params = {"host": DEFAULT_HOST, "port": DEFAULT_PORT}
    params.update(overrides)
    return clickhouse_connect.get_client(**params)


def main() -> None:
    client = get_client()
    print(f"Connected to ClickHouse {client.server_version} at {DEFAULT_HOST}:{DEFAULT_PORT}")
    result = client.query("SELECT version(), uptime()")
    version, uptime = result.result_rows[0]
    print(f"version={version} uptime={uptime}s")
