package httpapi

import (
	"context"
	"fmt"
	"math/rand/v2"
	"net/http"
	"strings"
	"time"
)

// Range is an inclusive latency band. The zero value means no delay.
type Range struct {
	Min, Max time.Duration
}

// ParseRange parses "300ms-800ms", a single duration ("500ms") or "" / "0" (no delay).
func ParseRange(s string) (Range, error) {
	s = strings.TrimSpace(s)
	if s == "" || s == "0" {
		return Range{}, nil
	}
	lo, hi, found := strings.Cut(s, "-")
	minD, err := time.ParseDuration(lo)
	if err != nil {
		return Range{}, fmt.Errorf("invalid latency %q: %w", s, err)
	}
	maxD := minD
	if found {
		if maxD, err = time.ParseDuration(hi); err != nil {
			return Range{}, fmt.Errorf("invalid latency %q: %w", s, err)
		}
	}
	if minD < 0 || maxD < minD {
		return Range{}, fmt.Errorf("invalid latency %q: need 0 <= min <= max", s)
	}
	return Range{Min: minD, Max: maxD}, nil
}

func (r Range) String() string {
	if r.Min == r.Max {
		return r.Min.String()
	}
	return r.Min.String() + "-" + r.Max.String()
}

// Pick maps u in [0, 1) onto the band.
func (r Range) Pick(u float64) time.Duration {
	return r.Min + time.Duration(u*float64(r.Max-r.Min+1))
}

// Chaos adds latency and random 500s to /tasks routes, like the iOS MockNetworkPolicy.live.
// The zero value is off.
type Chaos struct {
	ReadLatency  Range   // GET
	WriteLatency Range   // POST, PUT, DELETE
	FailureRate  float64 // 0…1

	// Rand returns a value in [0, 1). Defaults to math/rand/v2.Float64.
	Rand func() float64
	// Sleep waits d or until ctx is done. Defaults to a timer-based sleep.
	Sleep func(ctx context.Context, d time.Duration) error
}

// Enabled reports whether chaos changes any behaviour.
func (c Chaos) Enabled() bool {
	return c.ReadLatency != (Range{}) || c.WriteLatency != (Range{}) || c.FailureRate > 0
}

// Middleware applies the delay, then the failure roll, to /tasks routes only.
func (c Chaos) Middleware(next http.Handler) http.Handler {
	if !c.Enabled() {
		return next
	}
	if c.Rand == nil {
		c.Rand = rand.Float64
	}
	if c.Sleep == nil {
		c.Sleep = sleepContext
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/tasks" && !strings.HasPrefix(r.URL.Path, "/tasks/") {
			next.ServeHTTP(w, r)
			return
		}
		band := c.WriteLatency
		if r.Method == http.MethodGet || r.Method == http.MethodHead {
			band = c.ReadLatency
		}
		if band != (Range{}) {
			if err := c.Sleep(r.Context(), band.Pick(c.Rand())); err != nil {
				return // Client went away; nothing to send.
			}
		}
		if c.FailureRate > 0 && c.Rand() < c.FailureRate {
			writeError(w, http.StatusInternalServerError, "simulated failure")
			return
		}
		next.ServeHTTP(w, r)
	})
}

func sleepContext(ctx context.Context, d time.Duration) error {
	if d <= 0 {
		return ctx.Err()
	}
	t := time.NewTimer(d)
	defer t.Stop()
	select {
	case <-t.C:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}
