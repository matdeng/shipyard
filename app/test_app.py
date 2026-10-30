import pytest

from app import app


@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as c:
        yield c


def test_health(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.get_json()["status"] == "ok"


def test_ready_with_memory_store(client):
    assert client.get("/ready").status_code == 200


def test_info_counts_visits(client):
    first = client.get("/api/info").get_json()["visits"]
    second = client.get("/api/info").get_json()["visits"]
    assert second == first + 1


def test_info_reports_who_served(client):
    r = client.get("/api/info")
    assert r.get_json()["served_by"]
    assert r.headers["X-Served-By"]


def test_post_and_list_message(client):
    r = client.post("/api/messages", json={"name": "Ana", "text": "First deploy!"})
    assert r.status_code == 201
    msgs = client.get("/api/messages").get_json()["messages"]
    assert msgs[0]["text"] == "First deploy!"


def test_message_validation(client):
    r = client.post("/api/messages", json={"name": "", "text": "no name"})
    assert r.status_code == 400


def test_metrics_exposed(client):
    client.get("/health")
    body = client.get("/metrics").get_data(as_text=True)
    assert "shipyard_http_requests_total" in body
