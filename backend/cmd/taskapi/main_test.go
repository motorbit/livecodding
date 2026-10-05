package main

import (
	"io"
	"testing"
	"time"
)

func TestParseConfigDefaults(t *testing.T) {
	cfg, err := parseConfig(nil, func(string) string { return "" }, io.Discard)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.addr != ":8080" || cfg.store != "memory" || cfg.db != "./tasks.db" || cfg.logFormat != "text" || cfg.chaos.Enabled() {
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
		{"--store=postgres"}, {"--log-format=xml"}, {"--failure-rate=2"}, {"--failure-rate=x"},
		{"--read-latency=slow"}, {"--write-latency=3s-1s"}, {"extra"},
	} {
		if _, err := parseConfig(args, func(string) string { return "" }, io.Discard); err == nil {
			t.Errorf("parseConfig(%v): want error", args)
		}
	}
}
