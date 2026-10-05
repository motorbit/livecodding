package main

import (
	"context"
	"io"
	"path/filepath"
	"testing"
	"time"

	"github.com/motorbit/livecodding/backend/internal/store"
)

func TestParseConfigDefaults(t *testing.T) {
	cfg, err := parseConfig(nil, func(string) string { return "" }, io.Discard)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.addr != ":8080" || cfg.store != "memory" || cfg.db != "./tasks.db" || cfg.logFormat != "text" || cfg.seed != "filled" || cfg.chaos.Enabled() {
		t.Fatalf("defaults = %+v", cfg)
	}
}

func TestParseConfigEnvAndFlags(t *testing.T) {
	env := map[string]string{"ADDR": ":9000", "STORE": "sqlite", "DB": "/data/x.db", "FAILURE_RATE": "0.5"}
	cfg, err := parseConfig([]string{"--read-latency=300ms-800ms", "--failure-rate=0.15", "--log-format=json"},
		func(k string) string { return env[k] }, io.Discard)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.addr != ":9000" || cfg.store != "sqlite" || cfg.db != "/data/x.db" || cfg.logFormat != "json" {
		t.Fatalf("cfg = %+v", cfg)
	}
	if cfg.chaos.FailureRate != 0.15 || cfg.chaos.ReadLatency.Max != 800*time.Millisecond {
		t.Fatalf("chaos = %+v (flags must win over env)", cfg.chaos)
	}
}

func TestParseConfigRejectsBadValues(t *testing.T) {
	for _, args := range [][]string{
		{"--store=postgres"}, {"--seed=some"}, {"--log-format=xml"}, {"--failure-rate=2"}, {"--failure-rate=x"},
		{"--read-latency=slow"}, {"--write-latency=3s-1s"}, {"extra"},
	} {
		if _, err := parseConfig(args, func(string) string { return "" }, io.Discard); err == nil {
			t.Errorf("parseConfig(%v): want error", args)
		}
	}
}

func TestParseConfigSeed(t *testing.T) {
	cfg, err := parseConfig(nil, func(k string) string { return map[string]string{"SEED": "empty"}[k] }, io.Discard)
	if err != nil || cfg.seed != "empty" {
		t.Fatalf("SEED env: cfg.seed = %q, err = %v", cfg.seed, err)
	}
	cfg, err = parseConfig([]string{"--seed=filled"}, func(k string) string { return map[string]string{"SEED": "empty"}[k] }, io.Discard)
	if err != nil || cfg.seed != "filled" {
		t.Fatalf("flag over env: cfg.seed = %q, err = %v", cfg.seed, err)
	}
}

func TestOpenStoreSeedModes(t *testing.T) {
	ctx := context.Background()
	for _, storeKind := range []string{"memory", "sqlite"} {
		for seed, want := range map[string]int{"filled": len(store.Seeds()), "empty": 0} {
			cfg := config{store: storeKind, db: filepath.Join(t.TempDir(), "tasks.db"), seed: seed}
			st, err := openStore(ctx, cfg)
			if err != nil {
				t.Fatal(err)
			}
			got, err := st.List(ctx)
			_ = st.Close()
			if err != nil || len(got) != want {
				t.Errorf("store=%s seed=%s: %d tasks (err %v), want %d", storeKind, seed, len(got), err, want)
			}
		}
	}
}
