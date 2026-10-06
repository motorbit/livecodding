package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/motorbit/livecodding/backend/internal/store"
	"github.com/motorbit/livecodding/backend/internal/task"
)

const fixedID = "6F1E2D3C-4B5A-4978-8A6B-5C4D3E2F1A0B"

var seedID = store.Seeds()[0].ID

func newTestHandler(t *testing.T) (http.Handler, *store.Memory) {
	t.Helper()
	st := store.NewMemory(store.Seeds())
	return NewHandler(Config{Store: st, NewID: func() string { return fixedID }}), st
}

func do(t *testing.T, h http.Handler, method, target, body string) *httptest.ResponseRecorder {
	t.Helper()
	var r io.Reader
	if body != "" {
		r = strings.NewReader(body)
	}
	req := httptest.NewRequest(method, target, r)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if ct := rec.Header().Get("Content-Type"); ct != "application/json" {
		t.Errorf("%s %s: Content-Type = %q, want application/json", method, target, ct)
	}
	return rec
}

func decode[T any](t *testing.T, rec *httptest.ResponseRecorder) T {
	t.Helper()
	var v T
	if err := json.Unmarshal(rec.Body.Bytes(), &v); err != nil {
		t.Fatalf("decode %q: %v", rec.Body.String(), err)
	}
	return v
}

func wantStatus(t *testing.T, rec *httptest.ResponseRecorder, status int) {
	t.Helper()
	if rec.Code != status {
		t.Fatalf("status = %d, want %d; body %s", rec.Code, status, rec.Body.String())
	}
}

func wantError(t *testing.T, rec *httptest.ResponseRecorder, status int) string {
	t.Helper()
	wantStatus(t, rec, status)
	body := decode[map[string]string](t, rec)
	if body["error"] == "" || len(body) != 1 {
		t.Fatalf("error body = %s", rec.Body.String())
	}
	return body["error"]
}

func TestHealthz(t *testing.T) {
	h, _ := newTestHandler(t)
	rec := do(t, h, http.MethodGet, "/healthz", "")
	wantStatus(t, rec, http.StatusOK)
	if got := strings.TrimSpace(rec.Body.String()); got != `{"status":"ok"}` {
		t.Fatalf("body = %s", got)
	}
}

func TestListTasks(t *testing.T) {
	h, _ := newTestHandler(t)
	rec := do(t, h, http.MethodGet, "/tasks", "")
	wantStatus(t, rec, http.StatusOK)
	got := decode[[]task.Task](t, rec)
	if len(got) != 4 || got[0].ID != "00000000-0000-0000-0000-000000000001" || got[3].ID != "00000000-0000-0000-0000-000000000004" {
		t.Fatalf("tasks = %+v", got)
	}
	// Wire shape: due_date omitted when absent.
	var raw []map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &raw)
	if _, ok := raw[0]["due_date"]; ok {
		t.Errorf("due_date should be omitted: %v", raw[0])
	}
	for _, k := range []string{"id", "title", "notes", "priority", "done"} {
		if _, ok := raw[0][k]; !ok {
			t.Errorf("missing key %q in %v", k, raw[0])
		}
	}
}

func TestListTasksEmptyIsArray(t *testing.T) {
	h := NewHandler(Config{Store: store.NewMemory(nil)})
	rec := do(t, h, http.MethodGet, "/tasks", "")
	wantStatus(t, rec, http.StatusOK)
	if got := strings.TrimSpace(rec.Body.String()); got != "[]" {
		t.Fatalf("body = %s, want []", got)
	}
}

func TestCreateTask(t *testing.T) {
	h, _ := newTestHandler(t)
	rec := do(t, h, http.MethodPost, "/tasks", `{"title":"  Ship it \n","notes":"n","priority":"High","due_date":"2026-10-05"}`)
	wantStatus(t, rec, http.StatusCreated)
	if loc := rec.Header().Get("Location"); loc != "/tasks/"+fixedID {
		t.Errorf("Location = %q", loc)
	}
	got := decode[task.Task](t, rec)
	if got.ID != fixedID || got.Title != "Ship it" || got.Notes != "n" || got.Priority != task.PriorityHigh ||
		got.Done || got.DueDate == nil || *got.DueDate != "2026-10-05" {
		t.Fatalf("created = %+v", got)
	}
	list := decode[[]task.Task](t, do(t, h, http.MethodGet, "/tasks", ""))
	if len(list) != 5 || list[4].ID != fixedID || list[4].Title != "Ship it" {
		t.Fatalf("list after create = %+v", list)
	}
}

func TestCreateTaskIgnoresClientIDAndDone(t *testing.T) {
	h, _ := newTestHandler(t)
	rec := do(t, h, http.MethodPost, "/tasks", `{"id":"`+seedID+`","title":"T","notes":"","priority":"Low","done":true,"due_date":null}`)
	wantStatus(t, rec, http.StatusCreated)
	got := decode[task.Task](t, rec)
	if got.ID != fixedID || got.Done || got.DueDate != nil {
		t.Fatalf("created = %+v", got)
	}
}

func TestCreateTaskIdempotencyKey(t *testing.T) {
	first := true
	newID := func() string {
		if first {
			first = false
			return fixedID
		}
		return task.NewID()
	}
	h := NewHandler(Config{Store: store.NewMemory(store.Seeds()), NewID: newID})
	post := func(key, body string) *httptest.ResponseRecorder {
		req := httptest.NewRequest(http.MethodPost, "/tasks", strings.NewReader(body))
		req.Header.Set("Idempotency-Key", key)
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		return rec
	}
	const key = "5A0B6C1D-2E3F-4A5B-8C6D-7E8F9A0B1C2D"

	wantStatus(t, post(key, `{"title":"Once","notes":"","priority":"Low"}`), http.StatusCreated)
	replay := post(key, `{"title":"Once","notes":"","priority":"Low"}`)
	wantStatus(t, replay, http.StatusOK)
	if got := decode[task.Task](t, replay); got.ID != fixedID || got.Title != "Once" {
		t.Fatalf("replay = %+v", got)
	}
	if loc := replay.Header().Get("Location"); loc != "/tasks/"+fixedID {
		t.Errorf("Location = %q", loc)
	}
	if list := decode[[]task.Task](t, do(t, h, http.MethodGet, "/tasks", "")); len(list) != 5 {
		t.Fatalf("count = %d, want 5", len(list))
	}

	wantStatus(t, do(t, h, http.MethodDelete, "/tasks/"+fixedID, ""), http.StatusNoContent)
	wantError(t, post(key, `{"title":"Once","notes":"","priority":"Low"}`), http.StatusNotFound)

	wantError(t, post("bad key!", `{"title":"T","notes":"","priority":"Low"}`), http.StatusBadRequest)
	wantError(t, post(key, `{"title":" ","notes":"","priority":"Low"}`), http.StatusBadRequest)
}

func TestCreateTaskValidation(t *testing.T) {
	cases := map[string]string{
		"empty title":           `{"title":"","notes":"","priority":"Low"}`,
		"whitespace title":      `{"title":" \n\t ","notes":"","priority":"Low"}`,
		"unknown priority":      `{"title":"T","notes":"","priority":"Urgent"}`,
		"lowercase priority":    `{"title":"T","notes":"","priority":"low"}`,
		"invalid due date":      `{"title":"T","notes":"","priority":"Low","due_date":"2026-02-30"}`,
		"due date with time":    `{"title":"T","notes":"","priority":"Low","due_date":"2026-10-05T10:00:00Z"}`,
		"malformed JSON":        `{"title":`,
		"not an object":         `["T"]`,
		"missing priority":      `{"title":"T","notes":""}`,
		"wrong type":            `{"title":"T","notes":"","priority":"Low","due_date":20261005}`,
		"trailing data":         `{"title":"T","notes":"","priority":"Low"}{}`,
		"empty body":            ``,
		"oversized body (1MiB)": `{"title":"T","notes":"` + strings.Repeat("x", MaxBodyBytes) + `","priority":"Low"}`,
	}
	for name, body := range cases {
		t.Run(name, func(t *testing.T) {
			h, st := newTestHandler(t)
			msg := wantError(t, do(t, h, http.MethodPost, "/tasks", body), http.StatusBadRequest)
			if strings.Contains(msg, "Urgent") || strings.Contains(msg, "2026") {
				t.Errorf("error echoes input: %q", msg)
			}
			if list, _ := st.List(context.Background()); len(list) != 4 {
				t.Errorf("store changed: %d tasks", len(list))
			}
		})
	}
}

func TestCreateTaskAllowsEmptyNotes(t *testing.T) {
	h, _ := newTestHandler(t)
	wantStatus(t, do(t, h, http.MethodPost, "/tasks", `{"title":"T","notes":"","priority":"Medium"}`), http.StatusCreated)
}

func TestUpdateTask(t *testing.T) {
	h, _ := newTestHandler(t)
	body := `{"id":"` + seedID + `","title":"  Renewed  ","notes":"done","priority":"Low","done":true,"due_date":"2026-11-01"}`
	rec := do(t, h, http.MethodPut, "/tasks/"+seedID, body)
	wantStatus(t, rec, http.StatusOK)
	got := decode[task.Task](t, rec)
	if got.ID != seedID || got.Title != "Renewed" || got.Notes != "done" || got.Priority != task.PriorityLow ||
		!got.Done || got.DueDate == nil || *got.DueDate != "2026-11-01" {
		t.Fatalf("updated = %+v", got)
	}
	list := decode[[]task.Task](t, do(t, h, http.MethodGet, "/tasks", ""))
	if list[0].Title != "Renewed" || len(list) != 4 {
		t.Fatalf("list = %+v", list)
	}
}

func TestUpdateTaskIsCaseInsensitiveOnIDs(t *testing.T) {
	st := store.NewMemory([]task.Task{{ID: fixedID, Title: "T", Priority: task.PriorityLow}})
	h := NewHandler(Config{Store: st})
	lower := strings.ToLower(fixedID)
	rec := do(t, h, http.MethodPut, "/tasks/"+lower, `{"id":"`+fixedID+`","title":"T2","notes":"","priority":"Low","done":false}`)
	wantStatus(t, rec, http.StatusOK)
	if got := decode[task.Task](t, rec); got.ID != fixedID {
		t.Fatalf("id = %q", got.ID)
	}
}

func TestUpdateTaskClearsDueDateWithNull(t *testing.T) {
	h, _ := newTestHandler(t)
	put := func(due string) task.Task {
		rec := do(t, h, http.MethodPut, "/tasks/"+seedID, `{"id":"`+seedID+`","title":"T","notes":"","priority":"Low","done":false,"due_date":`+due+`}`)
		wantStatus(t, rec, http.StatusOK)
		return decode[task.Task](t, rec)
	}
	put(`"2026-01-01"`)
	if got := put(`null`); got.DueDate != nil {
		t.Fatalf("due date = %v, want nil", *got.DueDate)
	}
}

func TestUpdateTaskErrors(t *testing.T) {
	unknown := "11111111-2222-4333-8444-555555555555"
	valid := func(id string) string {
		return `{"id":"` + id + `","title":"T","notes":"","priority":"Low","done":false}`
	}
	cases := []struct {
		name, path, body string
		status           int
	}{
		{"unknown id", "/tasks/" + unknown, valid(unknown), http.StatusNotFound},
		{"invalid path uuid", "/tasks/not-a-uuid", valid(seedID), http.StatusNotFound},
		{"id mismatch", "/tasks/" + seedID, valid(unknown), http.StatusBadRequest},
		{"invalid body id", "/tasks/" + seedID, valid("nope"), http.StatusBadRequest},
		{"missing body id", "/tasks/" + seedID, `{"title":"T","notes":"","priority":"Low","done":false}`, http.StatusBadRequest},
		{"missing done", "/tasks/" + seedID, `{"id":"` + seedID + `","title":"T","notes":"","priority":"Low"}`, http.StatusBadRequest},
		{"empty title", "/tasks/" + seedID, `{"id":"` + seedID + `","title":"  ","notes":"","priority":"Low","done":false}`, http.StatusBadRequest},
		{"unknown priority", "/tasks/" + seedID, `{"id":"` + seedID + `","title":"T","notes":"","priority":"Urgent","done":false}`, http.StatusBadRequest},
		{"invalid due date", "/tasks/" + seedID, `{"id":"` + seedID + `","title":"T","notes":"","priority":"Low","done":false,"due_date":"2026-13-01"}`, http.StatusBadRequest},
		{"malformed JSON", "/tasks/" + seedID, `{`, http.StatusBadRequest},
		{"oversized body", "/tasks/" + seedID, `{"id":"` + seedID + `","title":"T","notes":"` + strings.Repeat("x", MaxBodyBytes) + `","priority":"Low","done":false}`, http.StatusBadRequest},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			h, st := newTestHandler(t)
			wantError(t, do(t, h, http.MethodPut, tc.path, tc.body), tc.status)
			if list, _ := st.List(context.Background()); list[0].Title != store.Seeds()[0].Title {
				t.Error("store changed")
			}
		})
	}
}

func TestDeleteTask(t *testing.T) {
	h, _ := newTestHandler(t)
	rec := do(t, h, http.MethodDelete, "/tasks/"+strings.ToLower(seedID), "")
	wantStatus(t, rec, http.StatusNoContent)
	if rec.Body.Len() != 0 {
		t.Errorf("body = %q, want empty", rec.Body.String())
	}
	list := decode[[]task.Task](t, do(t, h, http.MethodGet, "/tasks", ""))
	if len(list) != 3 || list[0].ID != store.Seeds()[1].ID {
		t.Fatalf("list = %+v", list)
	}
	wantError(t, do(t, h, http.MethodDelete, "/tasks/"+seedID, ""), http.StatusNotFound)
}

func TestIfMatch(t *testing.T) {
	h, _ := newTestHandler(t)
	send := func(method, ifMatch, body string) *httptest.ResponseRecorder {
		req := httptest.NewRequest(method, "/tasks/"+seedID, strings.NewReader(body))
		if ifMatch != "" {
			req.Header.Set("If-Match", ifMatch)
		}
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		return rec
	}
	body := func(title string) string {
		return `{"id":"` + seedID + `","title":"` + title + `","notes":"","priority":"Low","done":false,"version":99}`
	}

	list := decode[[]task.Task](t, do(t, h, http.MethodGet, "/tasks", ""))
	if list[0].Version != 1 {
		t.Fatalf("seed version = %d, want 1", list[0].Version)
	}
	rec := send(http.MethodPut, "1", body("Mine"))
	wantStatus(t, rec, http.StatusOK)
	if got := decode[task.Task](t, rec); got.Version != 2 {
		t.Fatalf("version = %d, want 2", got.Version)
	}
	wantError(t, send(http.MethodPut, "1", body("Stale")), http.StatusPreconditionFailed)
	wantError(t, send(http.MethodDelete, `"1"`, ""), http.StatusPreconditionFailed)
	if got := decode[[]task.Task](t, do(t, h, http.MethodGet, "/tasks", ""))[0]; got.Title != "Mine" {
		t.Fatalf("stale write applied: %+v", got)
	}
	rec = send(http.MethodPut, `"2"`, body("Quoted"))
	wantStatus(t, rec, http.StatusOK)
	rec = send(http.MethodPut, "*", body("Any"))
	wantStatus(t, rec, http.StatusOK)
	if got := decode[task.Task](t, rec); got.Version != 4 {
		t.Fatalf("version = %d, want 4", got.Version)
	}
	for _, bad := range []string{"abc", "0", "-1", `W/"4"`} {
		wantError(t, send(http.MethodPut, bad, body("x")), http.StatusBadRequest)
		wantError(t, send(http.MethodDelete, bad, ""), http.StatusBadRequest)
	}
	wantStatus(t, send(http.MethodDelete, "4", ""), http.StatusNoContent)
}

func TestDeleteTaskInvalidUUIDIsNotFound(t *testing.T) {
	h, _ := newTestHandler(t)
	wantError(t, do(t, h, http.MethodDelete, "/tasks/xyz", ""), http.StatusNotFound)
}

func TestUnknownRoutesAreJSON(t *testing.T) {
	h, _ := newTestHandler(t)
	wantError(t, do(t, h, http.MethodGet, "/nope", ""), http.StatusNotFound)
	rec := do(t, h, http.MethodPatch, "/tasks", "")
	wantError(t, rec, http.StatusMethodNotAllowed)
	if allow := rec.Header().Get("Allow"); !strings.Contains(allow, "POST") {
		t.Errorf("Allow = %q", allow)
	}
}

// failingStore fails every operation, to cover 500 paths.
type failingStore struct{}

var errBoom = errors.New("boom")

func (failingStore) List(context.Context) ([]task.Task, error) { return nil, errBoom }
func (failingStore) Create(context.Context, task.Task) (task.Task, error) {
	return task.Task{}, errBoom
}
func (failingStore) Update(context.Context, task.Task, int) (task.Task, error) {
	return task.Task{}, errBoom
}
func (failingStore) CreateOnce(context.Context, string, task.Task) (task.Task, bool, error) {
	return task.Task{}, false, errBoom
}
func (failingStore) Delete(context.Context, string, int) error { return errBoom }
func (failingStore) Close() error                              { return nil }

func TestStoreFailuresAre500(t *testing.T) {
	h := NewHandler(Config{Store: failingStore{}})
	cases := []struct{ method, path, body string }{
		{http.MethodGet, "/tasks", ""},
		{http.MethodPost, "/tasks", `{"title":"T","notes":"","priority":"Low"}`},
		{http.MethodPut, "/tasks/" + seedID, `{"id":"` + seedID + `","title":"T","notes":"","priority":"Low","done":false}`},
		{http.MethodDelete, "/tasks/" + seedID, ""},
	}
	for _, tc := range cases {
		t.Run(tc.method, func(t *testing.T) {
			if msg := wantError(t, do(t, h, tc.method, tc.path, tc.body), http.StatusInternalServerError); msg != "internal error" {
				t.Errorf("message = %q", msg)
			}
		})
	}
}
