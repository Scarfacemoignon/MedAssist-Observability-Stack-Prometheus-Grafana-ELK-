"""
MedAssist API - Application Flask pour l'etude de cas monitoring.
Plateforme de teleconsultation medicale.
Expose des endpoints REST avec metriques Prometheus, logs JSON,
et connexions MySQL/Redis.
"""

import json
import logging
import os
import random
import time
from datetime import datetime

import mysql.connector
import redis
from flask import Flask, Response, jsonify, request
from prometheus_client import (
    Counter,
    Histogram,
    Gauge,
    generate_latest,
    CONTENT_TYPE_LATEST,
    REGISTRY,
)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
MYSQL_HOST = os.getenv("MYSQL_HOST", "mysql")
MYSQL_PORT = int(os.getenv("MYSQL_PORT", 3306))
MYSQL_USER = os.getenv("MYSQL_USER", "root")
MYSQL_PASSWORD = os.getenv("MYSQL_PASSWORD", "medassist")
MYSQL_DATABASE = os.getenv("MYSQL_DATABASE", "medassist")

REDIS_HOST = os.getenv("REDIS_HOST", "redis")
REDIS_PORT = int(os.getenv("REDIS_PORT", 6379))

# ---------------------------------------------------------------------------
# JSON logging
# ---------------------------------------------------------------------------
class JSONFormatter(logging.Formatter):
    def format(self, record):
        log_record = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        if hasattr(record, "extra_fields"):
            log_record.update(record.extra_fields)
        return json.dumps(log_record)


handler = logging.StreamHandler()
handler.setFormatter(JSONFormatter())

logger = logging.getLogger("medassist")
logger.setLevel(logging.INFO)
logger.addHandler(handler)
# Prevent duplicate logs from the root logger
logger.propagate = False

# ---------------------------------------------------------------------------
# Prometheus metrics
# ---------------------------------------------------------------------------
REQUEST_COUNT = Counter(
    "flask_http_request_total",
    "Total HTTP requests",
    ["method", "endpoint", "status"],
)

REQUEST_DURATION = Histogram(
    "flask_http_request_duration_seconds",
    "HTTP request duration in seconds",
    ["method", "endpoint"],
    buckets=[0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0],
)

REQUESTS_IN_PROGRESS = Gauge(
    "flask_http_requests_in_progress",
    "Number of HTTP requests currently in progress",
    ["method", "endpoint"],
)

DB_CONNECTION_STATUS = Gauge(
    "medassist_db_connection_status",
    "MySQL connection status (1=connected, 0=disconnected)",
)

REDIS_CONNECTION_STATUS = Gauge(
    "medassist_redis_connection_status",
    "Redis connection status (1=connected, 0=disconnected)",
)

PAYMENT_ERRORS = Counter(
    "medassist_payment_errors_total",
    "Total payment processing errors",
)

CONSULTATION_COUNT = Counter(
    "medassist_consultations_total",
    "Total consultations created",
    ["status"],
)

# ---------------------------------------------------------------------------
# Flask application
# ---------------------------------------------------------------------------
app = Flask(__name__)

# ---------------------------------------------------------------------------
# Database helpers
# ---------------------------------------------------------------------------

def get_mysql_connection():
    """Return a MySQL connection or None on failure."""
    try:
        conn = mysql.connector.connect(
            host=MYSQL_HOST,
            port=MYSQL_PORT,
            user=MYSQL_USER,
            password=MYSQL_PASSWORD,
            database=MYSQL_DATABASE,
            connection_timeout=5,
        )
        DB_CONNECTION_STATUS.set(1)
        return conn
    except mysql.connector.Error as exc:
        DB_CONNECTION_STATUS.set(0)
        logger.error(
            "MySQL connection failed",
            extra={"extra_fields": {"error": str(exc)}},
        )
        return None


def get_redis_client():
    """Return a Redis client or None on failure."""
    try:
        client = redis.Redis(
            host=REDIS_HOST, port=REDIS_PORT, decode_responses=True, socket_timeout=5
        )
        client.ping()
        REDIS_CONNECTION_STATUS.set(1)
        return client
    except redis.RedisError as exc:
        REDIS_CONNECTION_STATUS.set(0)
        logger.error(
            "Redis connection failed",
            extra={"extra_fields": {"error": str(exc)}},
        )
        return None


# ---------------------------------------------------------------------------
# Middleware: instrument every request
# ---------------------------------------------------------------------------

@app.before_request
def before_request():
    request._start_time = time.time()
    endpoint = request.path
    REQUESTS_IN_PROGRESS.labels(method=request.method, endpoint=endpoint).inc()


@app.after_request
def after_request(response):
    endpoint = request.path
    duration = time.time() - getattr(request, "_start_time", time.time())

    # Skip /metrics to avoid polluting application metrics
    if endpoint != "/metrics":
        REQUEST_COUNT.labels(
            method=request.method,
            endpoint=endpoint,
            status=response.status_code,
        ).inc()
        REQUEST_DURATION.labels(
            method=request.method,
            endpoint=endpoint,
        ).observe(duration)

        logger.info(
            "request completed",
            extra={
                "extra_fields": {
                    "method": request.method,
                    "endpoint": endpoint,
                    "status": response.status_code,
                    "duration": round(duration, 4),
                    "remote_addr": request.remote_addr,
                }
            },
        )

    REQUESTS_IN_PROGRESS.labels(method=request.method, endpoint=endpoint).dec()
    return response


# ---------------------------------------------------------------------------
# Simulate random latency (50-500 ms) and occasional errors
# ---------------------------------------------------------------------------

def simulate_latency(min_ms=50, max_ms=500):
    """Sleep for a random duration to simulate processing."""
    delay = random.randint(min_ms, max_ms) / 1000.0
    time.sleep(delay)


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@app.route("/health")
def health():
    """Health check endpoint used by load balancers and probes."""
    mysql_ok = False
    redis_ok = False

    conn = get_mysql_connection()
    if conn:
        try:
            cursor = conn.cursor()
            cursor.execute("SELECT 1")
            cursor.fetchone()
            mysql_ok = True
        except Exception:
            pass
        finally:
            conn.close()

    r = get_redis_client()
    if r:
        redis_ok = True

    status = "healthy" if (mysql_ok and redis_ok) else "degraded"
    http_code = 200 if mysql_ok else 503

    return jsonify({
        "status": status,
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "checks": {
            "mysql": "ok" if mysql_ok else "error",
            "redis": "ok" if redis_ok else "error",
        },
    }), http_code


@app.route("/api/doctors")
def get_doctors():
    """Return the list of available doctors. Uses Redis cache when available."""
    simulate_latency(50, 300)

    # Try cache first
    r = get_redis_client()
    if r:
        cached = r.get("doctors")
        if cached:
            logger.info("doctors served from cache")
            return Response(cached, mimetype="application/json")

    conn = get_mysql_connection()
    if not conn:
        return jsonify({"error": "Database unavailable"}), 503

    try:
        cursor = conn.cursor(dictionary=True)
        cursor.execute(
            "SELECT id, first_name, last_name, specialty, available, consultation_price "
            "FROM doctors WHERE available = TRUE"
        )
        doctors = cursor.fetchall()
        for d in doctors:
            d["consultation_price"] = float(d["consultation_price"])
            d["available"] = bool(d["available"])

        payload = json.dumps({"doctors": doctors, "count": len(doctors)})

        # Cache for 60 seconds
        if r:
            r.setex("doctors", 60, payload)

        return Response(payload, mimetype="application/json")
    except Exception as exc:
        logger.error(
            "Failed to fetch doctors",
            extra={"extra_fields": {"error": str(exc)}},
        )
        return jsonify({"error": "Internal server error"}), 500
    finally:
        conn.close()


@app.route("/api/consultations", methods=["GET", "POST"])
def consultations():
    """GET: list consultations. POST: book a new consultation."""
    simulate_latency(100, 400)

    conn = get_mysql_connection()
    if not conn:
        return jsonify({"error": "Database unavailable"}), 503

    try:
        cursor = conn.cursor(dictionary=True)

        if request.method == "GET":
            cursor.execute(
                "SELECT c.id, c.patient_id, c.doctor_id, c.scheduled_at, "
                "c.duration_minutes, c.status, c.consultation_type, c.total_price, "
                "c.created_at, d.first_name AS doctor_first_name, d.last_name AS doctor_last_name, "
                "d.specialty "
                "FROM consultations c "
                "JOIN doctors d ON c.doctor_id = d.id "
                "ORDER BY c.scheduled_at DESC LIMIT 50"
            )
            consults = cursor.fetchall()
            for c in consults:
                c["total_price"] = float(c["total_price"])
                c["scheduled_at"] = c["scheduled_at"].isoformat() if c["scheduled_at"] else None
                c["created_at"] = c["created_at"].isoformat() if c["created_at"] else None
            return jsonify({"consultations": consults, "count": len(consults)})

        # POST - book consultation
        data = request.get_json(silent=True) or {}
        patient_id = data.get("patient_id", random.randint(1, 10))
        doctor_id = data.get("doctor_id", random.randint(1, 9))
        consultation_type = data.get("type", random.choice(["general", "follow_up", "urgent", "specialist"]))

        cursor.execute("SELECT consultation_price FROM doctors WHERE id = %s AND available = TRUE", (doctor_id,))
        row = cursor.fetchone()
        if not row:
            return jsonify({"error": "Doctor not found or unavailable"}), 404

        price = float(row["consultation_price"])
        scheduled = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")

        cursor.execute(
            "INSERT INTO consultations (patient_id, doctor_id, scheduled_at, duration_minutes, "
            "status, consultation_type, total_price) VALUES (%s, %s, %s, %s, %s, %s, %s)",
            (patient_id, doctor_id, scheduled, 30, "scheduled", consultation_type, price),
        )
        conn.commit()
        CONSULTATION_COUNT.labels(status="booked").inc()

        logger.info(
            "consultation booked",
            extra={
                "extra_fields": {
                    "consultation_id": cursor.lastrowid,
                    "patient_id": patient_id,
                    "doctor_id": doctor_id,
                    "type": consultation_type,
                    "price": price,
                }
            },
        )

        return jsonify({
            "consultation_id": cursor.lastrowid,
            "patient_id": patient_id,
            "doctor_id": doctor_id,
            "type": consultation_type,
            "price": price,
            "status": "scheduled",
        }), 201

    except Exception as exc:
        logger.error(
            "Consultation processing failed",
            extra={"extra_fields": {"error": str(exc)}},
        )
        return jsonify({"error": "Internal server error"}), 500
    finally:
        conn.close()


@app.route("/api/payment", methods=["GET", "POST"])
def payment():
    """
    Simulate a payment endpoint for consultations.
    ~5% error rate to generate realistic failure metrics.
    """
    simulate_latency(100, 500)

    # Simulate ~5% failure rate
    if random.random() < 0.05:
        PAYMENT_ERRORS.inc()
        CONSULTATION_COUNT.labels(status="payment_failed").inc()
        logger.error(
            "payment processing failed",
            extra={
                "extra_fields": {
                    "error": "Payment gateway timeout",
                    "gateway": "stripe-simulator",
                }
            },
        )
        return jsonify({
            "status": "error",
            "message": "Payment gateway timeout. Please retry.",
        }), 500

    CONSULTATION_COUNT.labels(status="payment_success").inc()
    logger.info(
        "payment processed successfully",
        extra={
            "extra_fields": {
                "amount": round(random.uniform(25, 60), 2),
                "currency": "EUR",
                "gateway": "stripe-simulator",
            }
        },
    )

    return jsonify({
        "status": "success",
        "transaction_id": f"txn_{random.randint(100000, 999999)}",
        "message": "Payment processed successfully",
    })


@app.route("/api/webhook/alert", methods=["POST"])
def alert_webhook():
    """
    Receive Alertmanager webhook notifications.
    Used to simulate SMS / Slack / email receivers during the exercise.
    """
    data = request.get_json(silent=True) or {}
    alerts = data.get("alerts", [])

    for alert in alerts:
        severity = alert.get("labels", {}).get("severity", "unknown")
        alertname = alert.get("labels", {}).get("alertname", "unknown")
        status = alert.get("status", "unknown")
        logger.warning(
            "ALERT RECEIVED",
            extra={
                "extra_fields": {
                    "alertname": alertname,
                    "severity": severity,
                    "status": status,
                    "starts_at": alert.get("startsAt"),
                    "description": alert.get("annotations", {}).get("summary", ""),
                }
            },
        )

    return jsonify({"status": "received", "alert_count": len(alerts)})


@app.route("/metrics")
def metrics():
    """Expose Prometheus metrics."""
    return Response(generate_latest(REGISTRY), mimetype=CONTENT_TYPE_LATEST)


# ---------------------------------------------------------------------------
# Startup
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    logger.info("MedAssist API starting up")
    app.run(host="0.0.0.0", port=5000, debug=False)
