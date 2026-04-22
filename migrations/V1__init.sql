-- V1: Initial schema
-- Runs before any service deploys

CREATE TABLE IF NOT EXISTS urls (
    id           BIGSERIAL PRIMARY KEY,
    short_code   VARCHAR(16) UNIQUE NOT NULL,
    original_url TEXT NOT NULL,
    created_at   TIMESTAMPTZ DEFAULT NOW(),
    click_count  BIGINT DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_urls_short_code ON urls(short_code);
CREATE INDEX IF NOT EXISTS idx_urls_created_at ON urls(created_at DESC);