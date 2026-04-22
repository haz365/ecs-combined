import os
import json
import time
import uuid
import hashlib
import logging
import boto3
import redis

from contextlib import asynccontextmanager
from datetime import datetime, timezone

from fastapi import FastAPI, HTTPException, Request, Response
from fastapi.responses import RedirectResponse
from pydantic import BaseModel, HttpUrl
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
import psycopg2
from psycopg2.extras import RealDictCursor

# ── Structured JSON logging ───────────────────────────────────────────────────

class JSONFormatter(logging.Formatter):
    def format(self, record):
        log = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "level":     record.levelname,
            "service":   "api",
            "message":   record.getMessage(),
        }
        if hasattr(record, "trace_id"):
            log["trace_id"] = record.trace_id
        if record.exc_info:
            log["exception"] = self.formatException(record.exc_info)
        return json.dumps(log)

handler = logging.StreamHandler()
handler.setFormatter(JSONFormatter())
logging.basicConfig(level=logging.INFO, handlers=[handler])
logger = logging.getLogger("api")

# ── Config ────────────────────────────────────────────────────────────────────

DB_HOST       = os.environ["DB_HOST"]
DB_PORT       = int(os.environ.get("DB_PORT", "5432"))
DB_NAME       = os.environ["DB_NAME"]
DB_USER       = os.environ["DB_USER"]
DB_PASSWORD   = os.environ["DB_PASSWORD"]
REDIS_HOST    = os.environ["REDIS_HOST"]
REDIS_PORT    = int(os.environ.get("REDIS_PORT", "6379"))
REDIS_TOKEN   = os.environ.get("REDIS_TOKEN", "")
SQS_QUEUE_URL = os.environ["SQS_QUEUE_URL"]
AWS_REGION    = os.environ.get("AWS_REGION", "eu-west-1")
BASE_URL      = os.environ.get("BASE_URL", "http://localhost:8080")
SHORT_SALT    = os.environ.get("SHORT_SALT", "ecs-combined")

# ── Prometheus metrics ────────────────────────────────────────────────────────

REQUEST_COUNT = Counter(
    "api_requests_total", "Total HTTP requests",
    ["method", "endpoint", "status_code"]
)
REQUEST_LATENCY = Histogram(
    "api_request_duration_seconds", "Request latency",
    ["method", "endpoint"],
    buckets=[0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5]
)
URLS_SHORTENED  = Counter("urls_shortened_total", "Total URLs shortened")
URL_REDIRECTS   = Counter("url_redirects_total",  "Total redirects served")

# ── DB / Redis / SQS helpers ──────────────────────────────────────────────────

def get_db():
    return psycopg2.connect(
        host=DB_HOST, port=DB_PORT, dbname=DB_NAME,
        user=DB_USER, password=DB_PASSWORD,
        cursor_factory=RealDictCursor,
        connect_timeout=5,
    )

def get_redis():
    kwargs = {
        "host": REDIS_HOST, "port": REDIS_PORT,
        "decode_responses": True,
    }
    # In prod Redis has TLS + auth token; locally it's plain
    if REDIS_TOKEN:
        kwargs["password"] = REDIS_TOKEN
    if os.environ.get("REDIS_TLS", "false").lower() == "true":
        kwargs["ssl"] = True
    return redis.Redis(**kwargs)

def get_sqs():
    return boto3.client("sqs", region_name=AWS_REGION)

# ── DB schema init ────────────────────────────────────────────────────────────

def init_db():
    conn = get_db()
    cur  = conn.cursor()
    try:
        cur.execute("""
            CREATE TABLE IF NOT EXISTS urls (
                id           BIGSERIAL PRIMARY KEY,
                short_code   VARCHAR(16) UNIQUE NOT NULL,
                original_url TEXT NOT NULL,
                created_at   TIMESTAMPTZ DEFAULT NOW(),
                click_count  BIGINT DEFAULT 0
            )
        """)
        conn.commit()
        logger.info("DB schema ready")
    except Exception as e:
        conn.rollback()
        logger.warning(f"DB schema init skipped: {e}")
    finally:
        cur.close()
        conn.close()

# ── App ───────────────────────────────────────────────────────────────────────

@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    yield

app = FastAPI(title="ecs-combined API", version="1.0.0", lifespan=lifespan)

# ── Middleware: trace ID + metrics ────────────────────────────────────────────

@app.middleware("http")
async def observe(request: Request, call_next):
    trace_id = request.headers.get("X-Trace-ID", str(uuid.uuid4()))
    request.state.trace_id = trace_id

    start    = time.time()
    response = await call_next(request)
    latency  = time.time() - start

    REQUEST_COUNT.labels(request.method, request.url.path, response.status_code).inc()
    REQUEST_LATENCY.labels(request.method, request.url.path).observe(latency)
    response.headers["X-Trace-ID"] = trace_id
    return response

# ── Models ────────────────────────────────────────────────────────────────────

class ShortenRequest(BaseModel):
    url: HttpUrl

class ShortenResponse(BaseModel):
    short_code:   str
    short_url:    str
    original_url: str

# ── Routes ────────────────────────────────────────────────────────────────────

@app.get("/health")
def health():
    checks = {}
    try:
        conn = get_db()
        conn.cursor().execute("SELECT 1")
        conn.close()
        checks["db"] = "ok"
    except Exception as e:
        checks["db"] = str(e)
    try:
        get_redis().ping()
        checks["redis"] = "ok"
    except Exception as e:
        checks["redis"] = str(e)

    healthy = all(v == "ok" for v in checks.values())
    return Response(
        content=json.dumps({"status": "ok" if healthy else "degraded", "checks": checks}),
        media_type="application/json",
        status_code=200 if healthy else 503,
    )

@app.get("/metrics")
def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)

@app.post("/shorten", response_model=ShortenResponse)
def shorten(body: ShortenRequest, request: Request):
    trace_id = getattr(request.state, "trace_id", str(uuid.uuid4()))
    original = str(body.url)

    short_code = hashlib.sha256(
        f"{original}{SHORT_SALT}".encode()
    ).hexdigest()[:8]

    conn = get_db()
    cur  = conn.cursor()
    try:
        cur.execute("""
            INSERT INTO urls (short_code, original_url)
            VALUES (%s, %s)
            ON CONFLICT (short_code) DO UPDATE SET original_url = EXCLUDED.original_url
            RETURNING short_code, original_url
        """, (short_code, original))
        row = cur.fetchone()
        conn.commit()
    except Exception as e:
        conn.rollback()
        logger.error(f"DB error: {e}", extra={"trace_id": trace_id})
        raise HTTPException(500, "Database error")
    finally:
        cur.close()
        conn.close()

    URLS_SHORTENED.inc()
    logger.info(f"shortened {original} -> {short_code}", extra={"trace_id": trace_id})

    return ShortenResponse(
        short_code=row["short_code"],
        short_url=f"{BASE_URL}/r/{row['short_code']}",
        original_url=row["original_url"],
    )

@app.get("/r/{short_code}")
def redirect(short_code: str, request: Request):
    trace_id = getattr(request.state, "trace_id", str(uuid.uuid4()))

    # Cache check first
    try:
        cached = get_redis().get(f"url:{short_code}")
        if cached:
            _publish_click(short_code, trace_id)
            URL_REDIRECTS.inc()
            return RedirectResponse(url=cached, status_code=302)
    except Exception:
        pass

    conn = get_db()
    cur  = conn.cursor()
    try:
        cur.execute("SELECT original_url FROM urls WHERE short_code = %s", (short_code,))
        row = cur.fetchone()
    finally:
        cur.close()
        conn.close()

    if not row:
        raise HTTPException(404, "Not found")

    original = row["original_url"]

    try:
        get_redis().setex(f"url:{short_code}", 3600, original)
    except Exception:
        pass

    _publish_click(short_code, trace_id)
    URL_REDIRECTS.inc()
    logger.info(f"redirect {short_code} -> {original}", extra={"trace_id": trace_id})
    return RedirectResponse(url=original, status_code=302)

@app.get("/urls")
def list_urls(limit: int = 20, offset: int = 0):
    conn = get_db()
    cur  = conn.cursor()
    try:
        cur.execute(
            "SELECT short_code, original_url, created_at, click_count "
            "FROM urls ORDER BY created_at DESC LIMIT %s OFFSET %s",
            (limit, offset)
        )
        rows = cur.fetchall()
    finally:
        cur.close()
        conn.close()
    return {"urls": [dict(r) for r in rows]}

# ── Helpers ───────────────────────────────────────────────────────────────────

def _publish_click(short_code: str, trace_id: str):
    try:
        get_sqs().send_message(
            QueueUrl=SQS_QUEUE_URL,
            MessageBody=json.dumps({
                "short_code": short_code,
                "timestamp":  datetime.now(timezone.utc).isoformat(),
                "trace_id":   trace_id,
            }),
        )
    except Exception as e:
        logger.warning(f"SQS publish failed: {e}", extra={"trace_id": trace_id})