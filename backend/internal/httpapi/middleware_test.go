package httpapi

import (
	"bytes"
	"encoding/json"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/motorbit/livecodding/backend/internal/store"
)

func TestAccessLogRedactsEverythingButTheBasics(t *testing.T) {
	var buf bytes.Buffer
	logger := slog.New(slog.NewJSONHandler(&buf, nil))
	h := NewHandler(Config{Store: store.NewMemory(store.Seeds()), Logger: logger})

	const secret = "s3cr3t-value"
	body := `{"title":"` + secret + `-title","notes":"` + secret + `-notes","priority":"Low"}`
	req := httptest.NewRequest(http.MethodPost, "/tasks?token="+secret+"-query", strings.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+secret+"-auth")
	req.Header.Set("Cookie", "session="+secret+"-cookie")
	req.Header.Set("X-Request-ID", "req-123")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	wantStatus(t, rec, http.StatusCreated)
	if !strings.Contains(rec.Body.String(), secret) {
		t.Fatal("sanity: response should contain the title")
	}

	out := buf.String()
	if strings.Contains(out, secret) || strings.Contains(out, "token") || strings.Contains(out, "Bearer") {
		t.Fatalf("log leaks request data: %s", out)
	}
	var line map[string]any
	if err := json.Unmarshal([]byte(strings.TrimSpace(out)), &line); err != nil {
		t.Fatalf("want exactly one JSON line, got %q: %v", out, err)
	}
	want := map[string]any{"msg": "request", "method": "POST", "path": "/tasks", "status": float64(201), "request_id": "req-123"}
	for k, v := range want {
		if line[k] != v {
			t.Errorf("%s = %v, want %v", k, line[k], v)
		}
	}
	if _, ok := line["duration_ms"]; !ok {
		t.Error("missing duration_ms")
	}
}

func TestRequestID(t *testing.T) {
	h := NewHandler(Config{Store: store.NewMemory(nil)})
	call := func(headers map[string]string) http.Header {
		req := httptest.NewRequest(http.MethodGet, "/healthz", nil)
		for k, v := range headers {
			req.Header.Set(k, v)
		}
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		return rec.Header()
	}

	if got := call(map[string]string{"X-Request-ID": "abc-1"}).Get("X-Request-ID"); got != "abc-1" {
		t.Errorf("honour X-Request-ID: got %q", got)
	}
	hdr := call(map[string]string{"X-Correlation-ID": "corr.2"})
	if hdr.Get("X-Request-ID") != "corr.2" || hdr.Get("X-Correlation-ID") != "corr.2" {
		t.Errorf("honour X-Correlation-ID: got %v", hdr)
	}
	generated := call(nil).Get("X-Request-ID")
	if len(generated) != 32 {
		t.Errorf("generated id = %q", generated)
	}
	if got := call(map[string]string{"X-Request-ID": "bad id\nINFO fake=1"}).Get("X-Request-ID"); got == "" || strings.ContainsAny(got, " \n=") {
		t.Errorf("unsafe id should be replaced, got %q", got)
	}
	if got := call(map[string]string{"X-Request-ID": strings.Repeat("a", 200)}).Get("X-Request-ID"); len(got) != 32 {
		t.Errorf("overlong id should be replaced, got %q", got)
	}
}

func TestRecoverer(t *testing.T) {
	var buf bytes.Buffer
	logger := slog.New(slog.NewTextHandler(&buf, nil))
	panicky := http.HandlerFunc(func(http.ResponseWriter, *http.Request) { panic("secret-panic-value") })
	h := requestID(accessLog(logger, recoverer(logger, panicky)))

	req := httptest.NewRequest(http.MethodGet, "/tasks", nil)
	req.Header.Set("X-Request-ID", "panic-1")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)

	wantError(t, rec, http.StatusInternalServerError)
	out := buf.String()
	if !strings.Contains(out, "panic recovered") || !strings.Contains(out, "request_id=panic-1") || !strings.Contains(out, "status=500") {
		t.Errorf("log = %s", out)
	}
	if strings.Contains(out, "secret-panic-value") {
		t.Errorf("panic value leaked: %s", out)
	}
}
