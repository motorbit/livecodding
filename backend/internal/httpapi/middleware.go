package httpapi

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"log/slog"
	"net/http"
	"time"
)

const (
	headerRequestID     = "X-Request-ID"
	headerCorrelationID = "X-Correlation-ID"
	maxRequestIDLen     = 128
)

type ctxKey struct{}

// RequestIDFrom returns the request ID stored by the request ID middleware, or "".
func RequestIDFrom(ctx context.Context) string {
	id, _ := ctx.Value(ctxKey{}).(string)
	return id
}

// requestID honours a safe incoming X-Request-ID or X-Correlation-ID, otherwise generates one,
// stores it in the context and echoes it in the response (under X-Request-ID, plus
// X-Correlation-ID when the client sent that header).
func requestID(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id := r.Header.Get(headerRequestID)
		if !validRequestID(id) {
			id = r.Header.Get(headerCorrelationID)
		}
		if !validRequestID(id) {
			id = newRequestID()
		}
		w.Header().Set(headerRequestID, id)
		if r.Header.Get(headerCorrelationID) != "" {
			w.Header().Set(headerCorrelationID, id)
		}
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), ctxKey{}, id)))
	})
}

// validRequestID accepts only short [A-Za-z0-9._-] values so a client can't inject log content.
func validRequestID(id string) bool {
	if id == "" || len(id) > maxRequestIDLen {
		return false
	}
	for _, c := range []byte(id) {
		ok := c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' ||
			c == '-' || c == '_' || c == '.'
		if !ok {
			return false
		}
	}
	return true
}

func newRequestID() string {
	var b [16]byte
	_, _ = rand.Read(b[:])
	return hex.EncodeToString(b[:])
}

// statusRecorder remembers the response status for the access log.
type statusRecorder struct {
	http.ResponseWriter
	status      int
	wroteHeader bool
}

func (s *statusRecorder) WriteHeader(code int) {
	if !s.wroteHeader {
		s.status, s.wroteHeader = code, true
	}
	s.ResponseWriter.WriteHeader(code)
}

func (s *statusRecorder) Write(b []byte) (int, error) {
	if !s.wroteHeader {
		s.status, s.wroteHeader = http.StatusOK, true
	}
	return s.ResponseWriter.Write(b)
}

func (s *statusRecorder) Unwrap() http.ResponseWriter { return s.ResponseWriter }

// statusClientClosed is logged (never sent) when the client went away before a response.
const statusClientClosed = 499

// accessLog writes one line per request: method, path (no query), status, duration_ms,
// request_id. Headers, bodies and query values are never logged.
func accessLog(log *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w}
		next.ServeHTTP(rec, r)
		status := rec.status
		if !rec.wroteHeader {
			status = http.StatusOK
			if r.Context().Err() != nil {
				status = statusClientClosed
			}
		}
		log.LogAttrs(r.Context(), slog.LevelInfo, "request",
			slog.String("method", r.Method),
			slog.String("path", r.URL.Path),
			slog.Int("status", status),
			slog.Int64("duration_ms", time.Since(start).Milliseconds()),
			slog.String("request_id", RequestIDFrom(r.Context())),
		)
	})
}

// recoverer turns a panic into a 500 and logs it with the request ID and the panic's type only,
// since its value may carry request data.
func recoverer(log *slog.Logger, next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			v := recover()
			if v == nil {
				return
			}
			if v == http.ErrAbortHandler {
				panic(v)
			}
			log.ErrorContext(r.Context(), "panic recovered",
				"request_id", RequestIDFrom(r.Context()), "panic_type", fmt.Sprintf("%T", v))
			writeError(w, http.StatusInternalServerError, "internal error")
		}()
		next.ServeHTTP(w, r)
	})
}
