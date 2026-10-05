// Command taskapi serves the Task Board API.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"

	"github.com/motorbit/livecodding/backend/internal/httpapi"
	"github.com/motorbit/livecodding/backend/internal/store"
)

const shutdownTimeout = 10 * time.Second

type config struct {
	addr      string
	store     string
	db        string
	logFormat string
	chaos     httpapi.Chaos
}

func main() {
	if err := run(os.Args[1:], os.Stderr); err != nil {
		fmt.Fprintln(os.Stderr, "taskapi:", err)
		os.Exit(1)
	}
}

func run(args []string, stderr io.Writer) error {
	cfg, err := parseConfig(args, os.Getenv, stderr)
	if err != nil {
		return err
	}
	logger := newLogger(cfg.logFormat, stderr)

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	st, err := openStore(ctx, cfg)
	if err != nil {
		return err
	}
	defer func() { _ = st.Close() }()

	srv := &http.Server{
		Addr:              cfg.addr,
		Handler:           httpapi.NewHandler(httpapi.Config{Store: st, Logger: logger, Chaos: cfg.chaos}),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       15 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       60 * time.Second,
		MaxHeaderBytes:    64 << 10,
		ErrorLog:          slog.NewLogLogger(logger.Handler(), slog.LevelWarn),
	}

	errc := make(chan error, 1)
	go func() {
		logger.Info("listening", "addr", cfg.addr, "store", cfg.store,
			"chaos", cfg.chaos.Enabled(),
			"read_latency", cfg.chaos.ReadLatency.String(),
			"write_latency", cfg.chaos.WriteLatency.String(),
			"failure_rate", cfg.chaos.FailureRate)
		errc <- srv.ListenAndServe()
	}()

	select {
	case err := <-errc:
		return err
	case <-ctx.Done():
	}
	logger.Info("shutting down")
	shutdownCtx, cancel := context.WithTimeout(context.Background(), shutdownTimeout)
	defer cancel()
	if err := srv.Shutdown(shutdownCtx); err != nil {
		return fmt.Errorf("shutdown: %w", err)
	}
	if err := <-errc; !errors.Is(err, http.ErrServerClosed) {
		return err
	}
	logger.Info("stopped")
	return nil
}

func parseConfig(args []string, getenv func(string) string, output io.Writer) (config, error) {
	env := func(key, def string) string {
		if v := getenv(key); v != "" {
			return v
		}
		return def
	}
	fs := flag.NewFlagSet("taskapi", flag.ContinueOnError)
	fs.SetOutput(output)
	var cfg config
	var readLatency, writeLatency, failureRate string
	fs.StringVar(&cfg.addr, "addr", env("ADDR", ":8080"), "listen address (env ADDR)")
	fs.StringVar(&cfg.store, "store", env("STORE", "memory"), "storage backend: memory or sqlite (env STORE)")
	fs.StringVar(&cfg.db, "db", env("DB", "./tasks.db"), "sqlite database path (env DB)")
	fs.StringVar(&cfg.logFormat, "log-format", env("LOG_FORMAT", "text"), "log format: text or json (env LOG_FORMAT)")
	fs.StringVar(&readLatency, "read-latency", env("READ_LATENCY", ""), "GET /tasks latency band, e.g. 300ms-800ms (env READ_LATENCY)")
	fs.StringVar(&writeLatency, "write-latency", env("WRITE_LATENCY", ""), "POST/PUT/DELETE latency band, e.g. 100ms-300ms (env WRITE_LATENCY)")
	fs.StringVar(&failureRate, "failure-rate", env("FAILURE_RATE", "0"), "probability 0..1 of a simulated 500 on /tasks routes (env FAILURE_RATE)")
	if err := fs.Parse(args); err != nil {
		return config{}, err
	}
	if fs.NArg() > 0 {
		return config{}, fmt.Errorf("unexpected arguments: %v", fs.Args())
	}

	var err error
	if cfg.chaos.ReadLatency, err = httpapi.ParseRange(readLatency); err != nil {
		return config{}, fmt.Errorf("--read-latency: %w", err)
	}
	if cfg.chaos.WriteLatency, err = httpapi.ParseRange(writeLatency); err != nil {
		return config{}, fmt.Errorf("--write-latency: %w", err)
	}
	if cfg.chaos.FailureRate, err = strconv.ParseFloat(failureRate, 64); err != nil ||
		cfg.chaos.FailureRate < 0 || cfg.chaos.FailureRate > 1 {
		return config{}, fmt.Errorf("--failure-rate: want a number in [0, 1], got %q", failureRate)
	}
	switch cfg.store {
	case "memory", "sqlite":
	default:
		return config{}, fmt.Errorf("--store: want memory or sqlite, got %q", cfg.store)
	}
	switch cfg.logFormat {
	case "text", "json":
	default:
		return config{}, fmt.Errorf("--log-format: want text or json, got %q", cfg.logFormat)
	}
	return cfg, nil
}

func newLogger(format string, w io.Writer) *slog.Logger {
	if format == "json" {
		return slog.New(slog.NewJSONHandler(w, nil))
	}
	return slog.New(slog.NewTextHandler(w, nil))
}

func openStore(ctx context.Context, cfg config) (store.Store, error) {
	if cfg.store == "sqlite" {
		return store.OpenSQLite(ctx, cfg.db, store.Seeds())
	}
	return store.NewMemory(store.Seeds()), nil
}
