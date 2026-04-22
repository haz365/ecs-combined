-- V2: Analytics tables
-- Worker depends on these existing before it starts

CREATE TABLE IF NOT EXISTS click_events (
    id         BIGSERIAL PRIMARY KEY,
    short_code VARCHAR(16) NOT NULL,
    clicked_at TIMESTAMPTZ NOT NULL,
    trace_id   VARCHAR(64),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_click_events_short_code ON click_events(short_code);
CREATE INDEX IF NOT EXISTS idx_click_events_clicked_at ON click_events(clicked_at);

CREATE TABLE IF NOT EXISTS url_stats (
    short_code  VARCHAR(16) PRIMARY KEY,
    click_count BIGINT DEFAULT 0,
    last_click  TIMESTAMPTZ
);