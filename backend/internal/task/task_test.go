package task

import (
	"errors"
	"strings"
	"testing"
)

func ptr(s string) *string { return &s }

func TestNormalizeTitle(t *testing.T) {
	tests := []struct {
		in, want string
		err      error
	}{
		{"Buy milk", "Buy milk", nil},
		{"  Buy milk \n", "Buy milk", nil},
		{"\t\r\n Buy\tmilk \u00a0\u2028", "Buy\tmilk", nil},
		{"", "", ErrEmptyTitle},
		{" \n\t\u00a0 ", "", ErrEmptyTitle},
	}
	for _, tt := range tests {
		got, err := NormalizeTitle(tt.in)
		if got != tt.want || !errors.Is(err, tt.err) {
			t.Errorf("NormalizeTitle(%q) = %q, %v; want %q, %v", tt.in, got, err, tt.want, tt.err)
		}
	}
}

func TestValidateDueDate(t *testing.T) {
	valid := []*string{nil, ptr("2026-10-05"), ptr("2024-02-29")}
	for _, d := range valid {
		if err := ValidateDueDate(d); err != nil {
			t.Errorf("ValidateDueDate(%v) = %v, want nil", d, err)
		}
	}
	invalid := []string{"", "2026-1-5", "2026-13-01", "2025-02-29", "05-10-2026", "2026-10-05T00:00:00Z", "tomorrow"}
	for _, d := range invalid {
		if err := ValidateDueDate(ptr(d)); !errors.Is(err, ErrInvalidDueDate) {
			t.Errorf("ValidateDueDate(%q) = %v, want ErrInvalidDueDate", d, err)
		}
	}
}

func TestNormalize(t *testing.T) {
	base := Task{ID: "X", Title: " A ", Priority: PriorityHigh}
	got, err := Normalize(base)
	if err != nil || got.Title != "A" {
		t.Fatalf("Normalize = %+v, %v", got, err)
	}
	bad := base
	bad.Priority = "high"
	if _, err := Normalize(bad); !errors.Is(err, ErrInvalidPriority) {
		t.Errorf("lowercase priority: err = %v", err)
	}
	bad = base
	bad.DueDate = ptr("2026-02-30")
	if _, err := Normalize(bad); !errors.Is(err, ErrInvalidDueDate) {
		t.Errorf("bad due date: err = %v", err)
	}
}

func TestNewFromDraftIsNotDone(t *testing.T) {
	got, err := NewFromDraft("ID", Draft{Title: " T ", Notes: "n", Priority: PriorityLow, DueDate: ptr("2026-01-01")})
	if err != nil {
		t.Fatal(err)
	}
	if got.ID != "ID" || got.Title != "T" || got.Done || *got.DueDate != "2026-01-01" {
		t.Errorf("NewFromDraft = %+v", got)
	}
}

func TestIDs(t *testing.T) {
	id := NewID()
	if parsed, err := ParseID(id); err != nil || parsed != id {
		t.Fatalf("ParseID(NewID()) = %q, %v; want %q", parsed, err, id)
	}
	if id[14] != '4' {
		t.Errorf("NewID() = %q, want version 4", id)
	}
	if NewID() == id {
		t.Error("NewID returned a duplicate")
	}
	got, err := ParseID("6f1e2d3c-4b5a-4978-8a6b-5c4d3e2f1a0b")
	if err != nil || got != "6F1E2D3C-4B5A-4978-8A6B-5C4D3E2F1A0B" {
		t.Errorf("lower-case ParseID = %q, %v", got, err)
	}
	for _, bad := range []string{"", "nope", "6f1e2d3c4b5a49788a6b5c4d3e2f1a0b", "6f1e2d3c-4b5a-4978-8a6b-5c4d3e2f1a0g", "{6f1e2d3c-4b5a-4978-8a6b-5c4d3e2f1a0}"} {
		if _, err := ParseID(bad); !errors.Is(err, ErrInvalidID) {
			t.Errorf("ParseID(%q) err = %v, want ErrInvalidID", bad, err)
		}
	}
}

func TestDecodeDraft(t *testing.T) {
	d, err := DecodeDraft(strings.NewReader(`{"title":"T","notes":"","priority":"Low","due_date":"2026-01-02"}`))
	if err != nil || d.Title != "T" || d.Priority != PriorityLow || d.DueDate == nil || *d.DueDate != "2026-01-02" {
		t.Fatalf("DecodeDraft = %+v, %v", d, err)
	}
	d, err = DecodeDraft(strings.NewReader(`{"title":"T","notes":"","priority":"Low","due_date":null}`))
	if err != nil || d.DueDate != nil {
		t.Fatalf("null due_date: %+v, %v", d, err)
	}
	malformed := []string{
		``, `{`, `[]`, `null`, `{"title":"T","notes":""}`, `{"notes":"","priority":"Low"}`,
		`{"title":"T","priority":"Low"}`, `{"title":1,"notes":"","priority":"Low"}`,
		`{"title":"T","notes":"","priority":"Low","due_date":5}`, `{"title":"T","notes":"","priority":"Low"} {}`,
	}
	for _, body := range malformed {
		if _, err := DecodeDraft(strings.NewReader(body)); !errors.Is(err, ErrMalformed) {
			t.Errorf("DecodeDraft(%q) err = %v, want ErrMalformed", body, err)
		}
	}
}

func TestDecodeTask(t *testing.T) {
	got, err := DecodeTask(strings.NewReader(`{"id":"a","title":"T","notes":"n","priority":"High","done":true}`))
	if err != nil || got.ID != "a" || !got.Done || got.DueDate != nil {
		t.Fatalf("DecodeTask = %+v, %v", got, err)
	}
	for _, body := range []string{
		`{"title":"T","notes":"n","priority":"High","done":true}`,
		`{"id":"a","title":"T","notes":"n","priority":"High"}`,
		`{"id":"a","title":"T","notes":"n","priority":"High","done":"yes"}`,
	} {
		if _, err := DecodeTask(strings.NewReader(body)); !errors.Is(err, ErrMalformed) {
			t.Errorf("DecodeTask(%q) err = %v, want ErrMalformed", body, err)
		}
	}
}
