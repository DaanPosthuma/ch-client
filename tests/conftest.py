import uuid

import pytest

from ch_client import get_client


@pytest.fixture(scope="session")
def client():
    c = get_client()
    yield c
    c.close()


@pytest.fixture
def temp_table(client):
    name = f"test_{uuid.uuid4().hex[:12]}"
    yield name
    client.command(f"DROP TABLE IF EXISTS {name}")
