package httpapi

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/motorbit/livecodding/backend/internal/store"
)

// fakeChaos records sleeps instead of sleeping and replays scripted random values.
type fakeChaos struct {
	rands  []float64
	sleeps []time.Duration
}

func (f *fakeChaos) rand() float64 {
	if len(f.rands) == 0 {
		return 0.99
	}
	v := f.rands[0]
	f.rands = f.rands[1:]
	return v
}

func (f *fakeChaos) sleep(ctx context.Context, d time.Duration) error {
	f.sleeps = append(f.sleeps, d)
	return ctx.Err()
}

func chaosHandler(f *fakeChaos, c Chaos) http.Handler {
	c.Rand, c.Sleep = f.rand, f.sleep
	return NewHandler(Config{Store: store.NewMemory(store.Seeds()), Chaos: c})
}

var challengeChaos = Chaos{
	ReadLatency:  Range{300 * time.Millisecond, 800 * time.Millisecond},
	WriteLatency: Range{100 * time.Millisecond, 300 * time.Millisecond},
	FailureRate:  0.15,
}

func TestChaosOffByDefault(t *testing.T) {
	f := &fakeChaos{}
	h := chaosHandler(f, Chaos{})
	wantStatus(t, do(t, h, http.MethodGet, "/tasks", ""), http.StatusOK)
	if len(f.sleeps) != 0 {
		t.Fatalf("slept %v", f.sleeps)
	}
}

func TestChaosSuccessPathDelaysReads(t *testing.T) {
	f := &fakeChaos{rands: []float64{0.5, 0.15}} // latency pick, failure roll (not < 0.15)
	h := chaosHandler(f, challengeChaos)
	wantStatus(t, do(t, h, http.MethodGet, "/tasks", ""), http.StatusOK)
	if len(f.sleeps) != 1 || f.sleeps[0] < 300*time.Millisecond || f.sleeps[0] > 800*time.Millisecond {
		t.Fatalf("sleeps = %v", f.sleeps)
	}
}

func TestChaosForcedFailure(t *testing.T) {
	f := &fakeChaos{rands: []float64{0, 0.149}}
	h := chaosHandler(f, challengeChaos)
	if msg := wantError(t, do(t, h, http.MethodPost, "/tasks", `{"title":"T","notes":"","priority":"Low"}`), http.StatusInternalServerError); msg != "simulated failure" {
		t.Fatalf("message = %q", msg)
	}
	// The failure happens before the handler: nothing was created.
	f.rands = []float64{0, 0.99}
	if got := decode[[]map[string]any](t, do(t, h, http.MethodGet, "/tasks", "")); len(got) != 4 {
		t.Fatalf("len = %d", len(got))
	}
}

func TestChaosLatencyBands(t *testing.T) {
	cases := []struct {
		method, path string
		u            float64
		want         time.Duration
	}{
		{http.MethodGet, "/tasks", 0, 300 * time.Millisecond},
		{http.MethodGet, "/tasks", 0.999999999, 800 * time.Millisecond},
		{http.MethodPost, "/tasks", 0, 100 * time.Millisecond},
		{http.MethodPut, "/tasks/" + seedID, 0.999999999, 300 * time.Millisecond},
		{http.MethodDelete, "/tasks/" + seedID, 0.5, 200 * time.Millisecond},
	}
	for _, tc := range cases {
		f := &fakeChaos{rands: []float64{tc.u, 0.99}}
		h := chaosHandler(f, challengeChaos)
		do(t, h, tc.method, tc.path, "")
		if len(f.sleeps) != 1 || f.sleeps[0].Round(time.Millisecond) != tc.want {
			t.Errorf("%s %s u=%v: sleeps = %v, want %v", tc.method, tc.path, tc.u, f.sleeps, tc.want)
		}
	}
}

func TestChaosExcludesHealthz(t *testing.T) {
	f := &fakeChaos{rands: []float64{0, 0}}
	h := chaosHandler(f, Chaos{ReadLatency: Range{time.Second, time.Second}, FailureRate: 1})
	wantStatus(t, do(t, h, http.MethodGet, "/healthz", ""), http.StatusOK)
	if len(f.sleeps) != 0 {
		t.Fatalf("healthz slept %v", f.sleeps)
	}
}

func TestChaosRespectsCancellation(t *testing.T) {
	f := &fakeChaos{rands: []float64{0, 0}}
	h := chaosHandler(f, Chaos{ReadLatency: Range{time.Second, time.Second}, FailureRate: 1})
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	req := httptest.NewRequestWithContext(ctx, http.MethodGet, "/tasks", nil)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Body.Len() != 0 {
		t.Fatalf("wrote %q after cancellation", rec.Body.String())
	}
}

func TestSleepContext(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	start := time.Now()
	if err := sleepContext(ctx, time.Hour); err == nil {
		t.Fatal("want ctx error")
	}
	if time.Since(start) > time.Second {
		t.Fatal("did not return promptly")
	}
	if err := sleepContext(context.Background(), 0); err != nil {
		t.Fatal(err)
	}
}

func TestParseRange(t *testing.T) {
	ok := map[string]Range{
		"":            {},
		"0":           {},
		"500ms":       {500 * time.Millisecond, 500 * time.Millisecond},
		"300ms-800ms": {300 * time.Millisecond, 800 * time.Millisecond},
		"1s-2s":       {time.Second, 2 * time.Second},
	}
	for in, want := range ok {
		if got, err := ParseRange(in); err != nil || got != want {
			t.Errorf("ParseRange(%q) = %v, %v; want %v", in, got, err, want)
		}
	}
	for _, in := range []string{"fast", "800ms-300ms", "-5ms", "1s-x"} {
		if _, err := ParseRange(in); err == nil {
			t.Errorf("ParseRange(%q): want error", in)
		}
	}
}
