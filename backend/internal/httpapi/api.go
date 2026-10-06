// Package httpapi exposes the Task API over HTTP using net/http's method/path patterns.
package httpapi

import (
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strconv"
	"strings"

	"github.com/motorbit/livecodding/backend/internal/store"
	"github.com/motorbit/livecodding/backend/internal/task"
)

// MaxBodyBytes caps request bodies; larger bodies get 400.
const MaxBodyBytes = 1 << 20

// Route is one registered method + path pattern. Routes is shared by the mux and the OpenAPI
// coverage test.
type Route struct {
	Method string
	Path   string
}

// Pattern returns the ServeMux pattern, e.g. "GET /tasks/{id}".
func (r Route) Pattern() string { return r.Method + " " + r.Path }

var (
	routeListTasks  = Route{http.MethodGet, "/tasks"}
	routeCreateTask = Route{http.MethodPost, "/tasks"}
	routeUpdateTask = Route{http.MethodPut, "/tasks/{id}"}
	routeDeleteTask = Route{http.MethodDelete, "/tasks/{id}"}
	routeHealth     = Route{http.MethodGet, "/healthz"}
)

// Routes lists every API route.
func Routes() []Route {
	return []Route{routeListTasks, routeCreateTask, routeUpdateTask, routeDeleteTask, routeHealth}
}

// Config wires the API.
type Config struct {
	Store  store.Store
	Logger *slog.Logger
	Chaos  Chaos
	// NewID generates ids for created tasks. Defaults to task.NewID.
	NewID func() string
}

// NewHandler returns the full handler: request ID → access log → recover → chaos → routes.
func NewHandler(cfg Config) http.Handler {
	if cfg.Logger == nil {
		cfg.Logger = slog.New(slog.DiscardHandler)
	}
	if cfg.NewID == nil {
		cfg.NewID = task.NewID
	}
	a := &api{store: cfg.Store, log: cfg.Logger, newID: cfg.NewID}

	mux := http.NewServeMux()
	mux.HandleFunc(routeListTasks.Pattern(), a.listTasks)
	mux.HandleFunc(routeCreateTask.Pattern(), a.createTask)
	mux.HandleFunc(routeUpdateTask.Pattern(), a.updateTask)
	mux.HandleFunc(routeDeleteTask.Pattern(), a.deleteTask)
	mux.HandleFunc(routeHealth.Pattern(), a.health)

	var h http.Handler = jsonFallback(mux)
	h = cfg.Chaos.Middleware(h)
	h = recoverer(cfg.Logger, h)
	h = accessLog(cfg.Logger, h)
	h = requestID(h)
	return h
}

type api struct {
	store store.Store
	log   *slog.Logger
	newID func() string
}

func (a *api) health(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (a *api) listTasks(w http.ResponseWriter, r *http.Request) {
	tasks, err := a.store.List(r.Context())
	if err != nil {
		a.internalError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, tasks)
}

func (a *api) createTask(w http.ResponseWriter, r *http.Request) {
	draft, err := task.DecodeDraft(http.MaxBytesReader(w, r.Body, MaxBodyBytes))
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	t, err := task.NewFromDraft(a.newID(), draft)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	key, hasKey := r.Header[headerIdempotencyKey]
	if !hasKey {
		created, err := a.store.Create(r.Context(), t)
		if err != nil {
			a.internalError(w, r, err)
			return
		}
		w.Header().Set("Location", "/tasks/"+created.ID)
		writeJSON(w, http.StatusCreated, created)
		return
	}
	if len(key) != 1 || !validRequestID(key[0]) {
		writeError(w, http.StatusBadRequest, "invalid Idempotency-Key")
		return
	}
	stored, created, err := a.store.CreateOnce(r.Context(), key[0], t)
	if errors.Is(err, store.ErrNotFound) {
		writeError(w, http.StatusNotFound, err.Error())
		return
	}
	if err != nil {
		a.internalError(w, r, err)
		return
	}
	w.Header().Set("Location", "/tasks/"+stored.ID)
	status := http.StatusCreated
	if !created {
		status = http.StatusOK
	}
	writeJSON(w, status, stored)
}

// headerIdempotencyKey makes POST /tasks safe to retry: a repeated key returns the task the
// first request created instead of creating another.
const headerIdempotencyKey = "Idempotency-Key"

func (a *api) updateTask(w http.ResponseWriter, r *http.Request) {
	id, err := task.ParseID(r.PathValue("id"))
	if err != nil {
		writeError(w, http.StatusNotFound, store.ErrNotFound.Error())
		return
	}
	ifVersion, ok := parseIfMatch(r)
	if !ok {
		writeError(w, http.StatusBadRequest, "invalid If-Match")
		return
	}
	body, err := task.DecodeTask(http.MaxBytesReader(w, r.Body, MaxBodyBytes))
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	bodyID, err := task.ParseID(body.ID)
	if err != nil || bodyID != id {
		writeError(w, http.StatusBadRequest, "body id must match path id")
		return
	}
	body.ID = id
	t, err := task.Normalize(body)
	if err != nil {
		writeError(w, http.StatusBadRequest, err.Error())
		return
	}
	updated, err := a.store.Update(r.Context(), t, ifVersion)
	if a.writeStoreError(w, err) {
		return
	}
	if err != nil {
		a.internalError(w, r, err)
		return
	}
	writeJSON(w, http.StatusOK, updated)
}

func (a *api) deleteTask(w http.ResponseWriter, r *http.Request) {
	id, err := task.ParseID(r.PathValue("id"))
	if err != nil {
		writeError(w, http.StatusNotFound, store.ErrNotFound.Error())
		return
	}
	ifVersion, ok := parseIfMatch(r)
	if !ok {
		writeError(w, http.StatusBadRequest, "invalid If-Match")
		return
	}
	err = a.store.Delete(r.Context(), id, ifVersion)
	if a.writeStoreError(w, err) {
		return
	}
	if err != nil {
		a.internalError(w, r, err)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusNoContent)
}

// headerIfMatch makes PUT and DELETE conditional on the task's version: a stale version gets 412.
const headerIfMatch = "If-Match"

// parseIfMatch reads If-Match as a task version: `3` or `"3"`. A missing header or `*` matches
// any version. ok is false for anything else.
func parseIfMatch(r *http.Request) (version int, ok bool) {
	values, present := r.Header[headerIfMatch]
	if !present {
		return store.AnyVersion, true
	}
	if len(values) != 1 {
		return 0, false
	}
	v := strings.TrimSpace(values[0])
	if v == "*" {
		return store.AnyVersion, true
	}
	if len(v) >= 2 && v[0] == '"' && v[len(v)-1] == '"' {
		v = v[1 : len(v)-1]
	}
	n, err := strconv.Atoi(v)
	if err != nil || n < 1 {
		return 0, false
	}
	return n, true
}

// writeStoreError writes 404 for ErrNotFound and 412 for ErrVersionMismatch. It reports whether
// the request is not handled further; other errors are left to the caller.
func (a *api) writeStoreError(w http.ResponseWriter, err error) bool {
	switch {
	case errors.Is(err, store.ErrNotFound):
		writeError(w, http.StatusNotFound, err.Error())
	case errors.Is(err, store.ErrVersionMismatch):
		writeError(w, http.StatusPreconditionFailed, err.Error())
	default:
		return false
	}
	return true
}

// internalError logs a store failure (never request data) and returns a generic 500.
func (a *api) internalError(w http.ResponseWriter, r *http.Request, err error) {
	a.log.ErrorContext(r.Context(), "store failure", "request_id", RequestIDFrom(r.Context()), "error", err)
	writeError(w, http.StatusInternalServerError, "internal error")
}

type errorBody struct {
	Error string `json:"error"`
}

func writeError(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, errorBody{Error: msg})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

// jsonFallback turns ServeMux's plain-text 404/405 replies into JSON error bodies, keeping the
// status code and the Allow header.
func jsonFallback(mux *http.ServeMux) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if h, pattern := mux.Handler(r); pattern == "" {
			capture := &headerCapture{header: http.Header{}, status: http.StatusOK}
			h.ServeHTTP(capture, r)
			if allow := capture.header.Get("Allow"); allow != "" {
				w.Header().Set("Allow", allow)
			}
			msg := "not found"
			if capture.status == http.StatusMethodNotAllowed {
				msg = "method not allowed"
			}
			writeError(w, capture.status, msg)
			return
		}
		mux.ServeHTTP(w, r)
	})
}

type headerCapture struct {
	header http.Header
	status int
}

func (c *headerCapture) Header() http.Header         { return c.header }
func (c *headerCapture) Write(b []byte) (int, error) { return len(b), nil }
func (c *headerCapture) WriteHeader(status int)      { c.status = status }
