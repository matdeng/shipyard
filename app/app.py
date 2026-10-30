"""Shipyard API: a tiny Flask app built to exercise a full DevOps toolchain.

Endpoints
  GET  /api/info      version, which pod served you, total visits (increments)
  GET  /api/messages  latest ship-log messages
  POST /api/messages  add a message  {"name": "...", "text": "..."}
  GET  /health        liveness: the process is up
  GET  /ready         readiness: the process can reach its storage
  GET  /metrics       Prometheus metrics
"""
import json
import os
import socket
import time
from collections import deque

from flask import Flask, g, jsonify, request
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

APP_VERSION = os.getenv("APP_VERSION", "dev")
REDIS_HOST = os.getenv("REDIS_HOST")          # unset = in-memory store (tests, quick runs)
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
HOSTNAME = socket.gethostname()               # in Kubernetes this is the pod name
MAX_MESSAGES = 50

app = Flask(__name__)

REQUESTS = Counter("shipyard_http_requests_total", "HTTP requests", ["method", "endpoint", "status"])
LATENCY = Histogram("shipyard_http_request_duration_seconds", "Request latency", ["endpoint"])
VISITS = Counter("shipyard_visits_total", "Visits counted by this instance")
MESSAGES = Counter("shipyard_messages_total", "Messages posted to this instance")


class MemoryStore:
    def __init__(self):
        self.visits = 0
        self.messages = deque(maxlen=MAX_MESSAGES)

    def ping(self):
        return True

    def incr_visits(self):
        self.visits += 1
        return self.visits

    def add_message(self, msg):
        self.messages.appendleft(msg)

    def list_messages(self, limit):
        return list(self.messages)[:limit]


class RedisStore:
    def __init__(self, host, port):
        import redis  # imported here so tests don't need a Redis server
        self.r = redis.Redis(host=host, port=port, socket_timeout=2, decode_responses=True)
        self.errors = redis.exceptions.RedisError

    def ping(self):
        try:
            return self.r.ping()
        except self.errors:
            return False

    def incr_visits(self):
        return self.r.incr("shipyard:visits")

    def add_message(self, msg):
        pipe = self.r.pipeline()
        pipe.lpush("shipyard:messages", json.dumps(msg))
        pipe.ltrim("shipyard:messages", 0, MAX_MESSAGES - 1)
        pipe.execute()

    def list_messages(self, limit):
        return [json.loads(m) for m in self.r.lrange("shipyard:messages", 0, limit - 1)]


store = RedisStore(REDIS_HOST, REDIS_PORT) if REDIS_HOST else MemoryStore()


@app.before_request
def start_timer():
    g.start = time.perf_counter()


@app.after_request
def record_metrics(response):
    # Use the route pattern, not the raw path, so metric labels stay low-cardinality.
    endpoint = request.url_rule.rule if request.url_rule else "unmatched"
    if endpoint != "/metrics":
        LATENCY.labels(endpoint).observe(time.perf_counter() - g.start)
        REQUESTS.labels(request.method, endpoint, response.status_code).inc()
    response.headers["X-Served-By"] = HOSTNAME
    return response


@app.get("/health")
def health():
    return jsonify(status="ok")


@app.get("/ready")
def ready():
    if store.ping():
        return jsonify(status="ready")
    return jsonify(status="storage unreachable"), 503


@app.get("/api/info")
def info():
    VISITS.inc()
    return jsonify(
        version=APP_VERSION,
        served_by=HOSTNAME,
        visits=store.incr_visits(),
        storage="redis" if REDIS_HOST else "memory",
    )


@app.get("/api/messages")
def list_messages():
    limit = min(int(request.args.get("limit", 20)), MAX_MESSAGES)
    return jsonify(messages=store.list_messages(limit))


@app.post("/api/messages")
def add_message():
    data = request.get_json(silent=True) or {}
    name = str(data.get("name", "")).strip()[:40]
    text = str(data.get("text", "")).strip()[:280]
    if not name or not text:
        return jsonify(error="Both name and text are required."), 400
    msg = {"name": name, "text": text, "pod": HOSTNAME, "version": APP_VERSION, "ts": int(time.time())}
    store.add_message(msg)
    MESSAGES.inc()
    return jsonify(msg), 201


@app.get("/metrics")
def metrics():
    return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000, debug=True)
