package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
	_ "github.com/lib/pq"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

// ── Config ────────────────────────────────────────────────────────────────────

type Config struct {
	DBHost      string
	DBPort      string
	DBName      string
	DBUser      string
	DBPassword  string
	SQSQueueURL string
	AWSRegion   string
	MetricsPort string
}

func loadConfig() Config {
	return Config{
		DBHost:      mustEnv("DB_HOST"),
		DBPort:      envOr("DB_PORT", "5432"),
		DBName:      mustEnv("DB_NAME"),
		DBUser:      mustEnv("DB_USER"),
		DBPassword:  mustEnv("DB_PASSWORD"),
		SQSQueueURL: mustEnv("SQS_QUEUE_URL"),
		AWSRegion:   envOr("AWS_REGION", "eu-west-1"),
		MetricsPort: envOr("METRICS_PORT", "9091"),
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
	msgsProcessed = prometheus.NewCounter(prometheus.CounterOpts{
		Name: "worker_messages_processed_total",
		Help: "SQS messages successfully processed",
	})
	msgsFailed = prometheus.NewCounter(prometheus.CounterOpts{
		Name: "worker_messages_failed_total",
		Help: "SQS messages that failed processing",
	})
	msgDuration = prometheus.NewHistogram(prometheus.HistogramOpts{
		Name:    "worker_message_processing_duration_seconds",
		Help:    "Time to process one SQS message",
		Buckets: prometheus.DefBuckets,
	})
)

func registerMetrics() {
	prometheus.MustRegister(msgsProcessed, msgsFailed, msgDuration)
}

// ── Click event ───────────────────────────────────────────────────────────────

type ClickEvent struct {
	ShortCode string `json:"short_code"`
	Timestamp string `json:"timestamp"`
	TraceID   string `json:"trace_id"`
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

func initDB(db *sql.DB) error {
	_, err := db.Exec(`
		CREATE TABLE IF NOT EXISTS click_events (
			id         BIGSERIAL PRIMARY KEY,
			short_code VARCHAR(16) NOT NULL,
			clicked_at TIMESTAMPTZ NOT NULL,
			trace_id   VARCHAR(64),
			created_at TIMESTAMPTZ DEFAULT NOW()
		);
		CREATE INDEX IF NOT EXISTS idx_click_short_code ON click_events(short_code);
		CREATE INDEX IF NOT EXISTS idx_click_clicked_at ON click_events(clicked_at);

		CREATE TABLE IF NOT EXISTS url_stats (
			short_code  VARCHAR(16) PRIMARY KEY,
			click_count BIGINT DEFAULT 0,
			last_click  TIMESTAMPTZ
		);
	`)
	return err
}

// ── Worker ────────────────────────────────────────────────────────────────────

type Worker struct {
	cfg    Config
	db     *sql.DB
	sqs    *sqs.Client
	logger *slog.Logger
}

func (w *Worker) processMessage(ctx context.Context, body string) error {
	var evt ClickEvent
	if err := json.Unmarshal([]byte(body), &evt); err != nil {
		return fmt.Errorf("unmarshal: %w", err)
	}

	clickedAt, err := time.Parse(time.RFC3339Nano, evt.Timestamp)
	if err != nil {
		clickedAt = time.Now().UTC()
	}

	tx, err := w.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin tx: %w", err)
	}
	defer tx.Rollback()

	_, err = tx.ExecContext(ctx,
		`INSERT INTO click_events (short_code, clicked_at, trace_id)
		 VALUES ($1, $2, $3)`,
		evt.ShortCode, clickedAt, evt.TraceID,
	)
	if err != nil {
		return fmt.Errorf("insert click_event: %w", err)
	}

	_, err = tx.ExecContext(ctx,
		`INSERT INTO url_stats (short_code, click_count, last_click)
		 VALUES ($1, 1, $2)
		 ON CONFLICT (short_code) DO UPDATE
		 SET click_count = url_stats.click_count + 1,
		     last_click  = EXCLUDED.last_click`,
		evt.ShortCode, clickedAt,
	)
	if err != nil {
		return fmt.Errorf("upsert url_stats: %w", err)
	}

	return tx.Commit()
}

func (w *Worker) run(ctx context.Context) {
	w.logger.Info("worker started", "queue", w.cfg.SQSQueueURL)

	for {
		select {
		case <-ctx.Done():
			w.logger.Info("shutting down")
			return
		default:
		}

		out, err := w.sqs.ReceiveMessage(ctx, &sqs.ReceiveMessageInput{
			QueueUrl:            aws.String(w.cfg.SQSQueueURL),
			MaxNumberOfMessages: 10,
			WaitTimeSeconds:     20,
		})
		if err != nil {
			w.logger.Error("SQS receive error", "err", err)
			time.Sleep(5 * time.Second)
			continue
		}

		for _, msg := range out.Messages {
			start := time.Now()
			err   := w.processMessage(ctx, aws.ToString(msg.Body))
			dur   := time.Since(start)
			msgDuration.Observe(dur.Seconds())

			if err != nil {
				w.logger.Error("processing failed",
					"err", err,
					"message_id", aws.ToString(msg.MessageId),
					"duration_ms", dur.Milliseconds(),
				)
				msgsFailed.Inc()
				// don't delete — let it reach DLQ after maxReceiveCount
				continue
			}

			w.sqs.DeleteMessage(ctx, &sqs.DeleteMessageInput{
				QueueUrl:      aws.String(w.cfg.SQSQueueURL),
				ReceiptHandle: msg.ReceiptHandle,
			})

			msgsProcessed.Inc()
			w.logger.Info("message processed",
				"duration_ms", dur.Milliseconds(),
			)
		}
	}
}

// ── Main ──────────────────────────────────────────────────────────────────────

func main() {
	log := slog.New(slog.NewJSONHandler(os.Stdout, nil))
	cfg := loadConfig()
	registerMetrics()

	db, err := connectDB(cfg)
	if err != nil {
		log.Error("DB connect failed", "err", err)
		os.Exit(1)
	}
	defer db.Close()

	if err := initDB(db); err != nil {
		log.Error("DB init failed", "err", err)
		os.Exit(1)
	}
	log.Info("DB ready")

	customResolver := aws.EndpointResolverWithOptionsFunc(
    func(service, region string, options ...interface{}) (aws.Endpoint, error) {
        if endpoint := os.Getenv("AWS_ENDPOINT_URL"); endpoint != "" {
            return aws.Endpoint{URL: endpoint, HostnameImmutable: true}, nil
        }
        return aws.Endpoint{}, &aws.EndpointNotFoundError{}
    },
)

awsCfg, err := config.LoadDefaultConfig(context.Background(),
    config.WithRegion(cfg.AWSRegion),
    config.WithEndpointResolverWithOptions(customResolver),
)

	if err != nil {
		log.Error("AWS config failed", "err", err)
		os.Exit(1)
	}

	// Metrics + health server
	mux := http.NewServeMux()
	mux.Handle("/metrics", promhttp.Handler())
	mux.HandleFunc("/health", func(w http.ResponseWriter, _ *http.Request) {
		if err := db.Ping(); err != nil {
			w.WriteHeader(503)
			w.Write([]byte(`{"status":"degraded"}`))
			return
		}
		w.Write([]byte(`{"status":"ok"}`))
	})
	go http.ListenAndServe(":"+cfg.MetricsPort, mux)

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	w := &Worker{cfg: cfg, db: db, sqs: sqs.NewFromConfig(awsCfg), logger: log}
	w.run(ctx)
}