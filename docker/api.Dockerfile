# syntax=docker/dockerfile:1.7
# ── Build stage ───────────────────────────────────────────────────────────────
FROM python:3.12.3-slim-bookworm AS builder

WORKDIR /build

RUN pip install --no-cache-dir --upgrade pip

COPY app/api/requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ── Runtime stage ─────────────────────────────────────────────────────────────
FROM python:3.12.3-slim-bookworm

RUN groupadd -r appuser && useradd -r -g appuser -s /sbin/nologin appuser

WORKDIR /app

COPY --from=builder /install /usr/local
COPY --chown=appuser:appuser app/api/main.py .

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

EXPOSE 8080

USER appuser

ENTRYPOINT ["python", "-m", "uvicorn", "main:app", \
            "--host", "0.0.0.0", \
            "--port", "8080", \
            "--workers", "2", \
            "--no-access-log"]