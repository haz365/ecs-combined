-- V3: Performance indexes
-- Added after load testing revealed slow queries

CREATE INDEX IF NOT EXISTS idx_click_events_short_code_clicked_at
    ON click_events(short_code, clicked_at DESC);

CREATE INDEX IF NOT EXISTS idx_url_stats_click_count
    ON url_stats(click_count DESC);