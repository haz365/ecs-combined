package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"time"

	_ "github.com/lib/pq"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// ── Config ────────────────────────────────────────────────────────────────────

type Config struct {
	DBHost     string
	DBPort     string
	DBName     string
	DBUser     string
	DBPassword string
	Port       string
}

func loadConfig() Config {
	return Config{
		DBHost:     mustEnv("DB_HOST"),
		DBPort:     envOr("DB_PORT", "5432"),
		DBName:     mustEnv("DB_NAME"),
		DBUser:     mustEnv("DB_USER"),
		DBPassword: mustEnv("DB_PASSWORD"),
		Port:       envOr("PORT", "8081"),
	}
}

func mustEnv(k string) string {
	v := os.Getenv(k)
	if v == "" {
		slog.Error("missing required env var", "key", k)
		os.Exit(1)
	}
	return v
}

func envOr(k, def string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return def
}

// ── Metrics ───────────────────────────────────────────────────────────────────

var (
	reqCount = prometheus.NewCounterVec(prometheus.CounterOpts{
		Name: "dashboard_requests_total",
		Help: "Total requests per endpoint",
	}, []string{"endpoint", "status"})

	reqDuration = prometheus.NewHistogramVec(prometheus.HistogramOpts{
		Name:    "dashboard_request_duration_seconds",
		Help:    "Request latency per endpoint",
		Buckets: prometheus.DefBuckets,
	}, []string{"endpoint"})
)

func init() {
	prometheus.MustRegister(reqCount, reqDuration)
}

// ── DB ────────────────────────────────────────────────────────────────────────

func connectDB(cfg Config) (*sql.DB, error) {
	dsn := fmt.Sprintf(
		"host=%s port=%s dbname=%s user=%s password=%s sslmode=disable",
		cfg.DBHost, cfg.DBPort, cfg.DBName, cfg.DBUser, cfg.DBPassword,
	)
	db, err := sql.Open("postgres", dsn)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(10)
	db.SetMaxIdleConns(5)
	db.SetConnMaxLifetime(5 * time.Minute)
	return db, nil
}

// ── Server ────────────────────────────────────────────────────────────────────

type Server struct {
	db     *sql.DB
	logger *slog.Logger
}

// Wraps a handler to record metrics
func (s *Server) track(endpoint string, h http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rw    := &rWriter{ResponseWriter: w, status: 200}
		h(rw, r)
		dur    := time.Since(start)
		reqCount.WithLabelValues(endpoint, fmt.Sprintf("%d", rw.status)).Inc()
		reqDuration.WithLabelValues(endpoint).Observe(dur.Seconds())
	}
}

type rWriter struct {
	http.ResponseWriter
	status int
}

func (rw *rWriter) WriteHeader(code int) {
	rw.status = code
	rw.ResponseWriter.WriteHeader(code)
}

// ── Handlers ──────────────────────────────────────────────────────────────────

func (s *Server) health(w http.ResponseWriter, _ *http.Request) {
	if err := s.db.Ping(); err != nil {
		w.WriteHeader(503)
		json.NewEncoder(w).Encode(map[string]string{"status": "degraded", "err": err.Error()})
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

// GET /top-urls?limit=10
func (s *Server) topURLs(w http.ResponseWriter, r *http.Request) {
	limit := 10
	fmt.Sscanf(r.URL.Query().Get("limit"), "%d", &limit)
	if limit <= 0 || limit > 100 {
		limit = 10
	}

	rows, err := s.db.QueryContext(r.Context(), `
		SELECT short_code, click_count, last_click
		FROM url_stats
		ORDER BY click_count DESC
		LIMIT $1
	`, limit)
	if err != nil {
		s.logger.Error("topURLs failed", "err", err)
		http.Error(w, "query error", 500)
		return
	}
	defer rows.Close()

	type Row struct {
		ShortCode  string     `json:"short_code"`
		ClickCount int64      `json:"click_count"`
		LastClick  *time.Time `json:"last_click,omitempty"`
	}

	var results []Row
	for rows.Next() {
		var row Row
		rows.Scan(&row.ShortCode, &row.ClickCount, &row.LastClick)
		results = append(results, row)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{
		"top_urls": results,
		"count":    len(results),
	})
}

// GET /hourly?short_code=abc&hours=24
func (s *Server) hourly(w http.ResponseWriter, r *http.Request) {
	shortCode := r.URL.Query().Get("short_code")
	hours := 24
	fmt.Sscanf(r.URL.Query().Get("hours"), "%d", &hours)
	if hours <= 0 || hours > 720 {
		hours = 24
	}

	query := `
		SELECT date_trunc('hour', clicked_at) AS hour, COUNT(*) AS clicks
		FROM click_events
		WHERE clicked_at >= NOW() - ($1 || ' hours')::interval
	`
	args := []any{hours}
	if shortCode != "" {
		query += " AND short_code = $2"
		args = append(args, shortCode)
	}
	query += " GROUP BY 1 ORDER BY 1"

	rows, err := s.db.QueryContext(r.Context(), query, args...)
	if err != nil {
		s.logger.Error("hourly failed", "err", err)
		http.Error(w, "query error", 500)
		return
	}
	defer rows.Close()

	type Bucket struct {
		Hour   time.Time `json:"hour"`
		Clicks int64     `json:"clicks"`
	}

	var buckets []Bucket
	for rows.Next() {
		var b Bucket
		rows.Scan(&b.Hour, &b.Clicks)
		buckets = append(buckets, b)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{
		"short_code": shortCode,
		"hours":      hours,
		"buckets":    buckets,
	})
}

// GET /recent?limit=50
func (s *Server) recent(w http.ResponseWriter, r *http.Request) {
	limit := 50
	fmt.Sscanf(r.URL.Query().Get("limit"), "%d", &limit)
	if limit <= 0 || limit > 500 {
		limit = 50
	}

	rows, err := s.db.QueryContext(r.Context(), `
		SELECT short_code, clicked_at, trace_id
		FROM click_events
		ORDER BY clicked_at DESC
		LIMIT $1
	`, limit)
	if err != nil {
		s.logger.Error("recent failed", "err", err)
		http.Error(w, "query error", 500)
		return
	}
	defer rows.Close()

	type Event struct {
		ShortCode string    `json:"short_code"`
		ClickedAt time.Time `json:"clicked_at"`
		TraceID   *string   `json:"trace_id,omitempty"`
	}

	var events []Event
	for rows.Next() {
		var e Event
		rows.Scan(&e.ShortCode, &e.ClickedAt, &e.TraceID)
		events = append(events, e)
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{
		"events": events,
		"count":  len(events),
	})
}

// GET /summary
func (s *Server) summary(w http.ResponseWriter, r *http.Request) {
	var totalURLs, totalClicks int64
	s.db.QueryRowContext(r.Context(),
		`SELECT COUNT(*), COALESCE(SUM(click_count), 0) FROM url_stats`,
	).Scan(&totalURLs, &totalClicks)

	var clicksLastHour int64
	s.db.QueryRowContext(r.Context(),
		`SELECT COUNT(*) FROM click_events WHERE clicked_at >= NOW() - INTERVAL '1 hour'`,
	).Scan(&clicksLastHour)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{
		"total_urls":       totalURLs,
		"total_clicks":     totalClicks,
		"clicks_last_hour": clicksLastHour,
		"generated_at":     time.Now().UTC(),
	})
}

// ── Main ──────────────────────────────────────────────────────────────────────

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	cfg := loadConfig()

	db, err := connectDB(cfg)
	if err != nil {
		log.Error("DB connect failed", "err", err)
		os.Exit(1)
	}
	defer db.Close()
	log.Info("DB connected")

	srv := &Server{db: db, logger: log}

	mux := http.NewServeMux()
	mux.HandleFunc("/health",   srv.health)
	mux.Handle("/metrics",      promhttp.Handler())
	mux.HandleFunc("/top-urls", srv.track("/top-urls", srv.topURLs))
	mux.HandleFunc("/hourly",   srv.track("/hourly",   srv.hourly))
	mux.HandleFunc("/recent",   srv.track("/recent",   srv.recent))
	mux.HandleFunc("/summary",  srv.track("/summary",  srv.summary))

	log.Info("dashboard listening", "port", cfg.Port)
	if err := http.ListenAndServe(":"+cfg.Port, mux); err != nil {
		log.Error("server error", "err", err)
		os.Exit(1)
	}
}