package task

import (
	"bytes"
	"encoding/json"
	"errors"
	"io"
)

// ErrMalformed is returned for bodies that are not a single JSON object of the expected shape,
// including missing required fields (the iOS DTOs' non-optional properties).
var ErrMalformed = errors.New("malformed JSON body")

// draftWire and taskWire use pointers to tell "missing" from "zero value", like Swift's Codable.
type draftWire struct {
	Title    *string         `json:"title"`
	Notes    *string         `json:"notes"`
	Priority *Priority       `json:"priority"`
	DueDate  json.RawMessage `json:"due_date"`
}

type taskWire struct {
	ID       *string         `json:"id"`
	Title    *string         `json:"title"`
	Notes    *string         `json:"notes"`
	Priority *Priority       `json:"priority"`
	Done     *bool           `json:"done"`
	DueDate  json.RawMessage `json:"due_date"`
}

// DecodeDraft decodes a TaskDraftDTO body. It does not validate values; see NewFromDraft.
func DecodeDraft(r io.Reader) (Draft, error) {
	var w draftWire
	if err := decodeSingle(r, &w); err != nil {
		return Draft{}, err
	}
	if w.Title == nil || w.Notes == nil || w.Priority == nil {
		return Draft{}, ErrMalformed
	}
	due, err := decodeDueDate(w.DueDate)
	if err != nil {
		return Draft{}, err
	}
	return Draft{Title: *w.Title, Notes: *w.Notes, Priority: *w.Priority, DueDate: due}, nil
}

// DecodeTask decodes a TaskDTO body. It does not validate values; see Normalize.
func DecodeTask(r io.Reader) (Task, error) {
	var w taskWire
	if err := decodeSingle(r, &w); err != nil {
		return Task{}, err
	}
	if w.ID == nil || w.Title == nil || w.Notes == nil || w.Priority == nil || w.Done == nil {
		return Task{}, ErrMalformed
	}
	due, err := decodeDueDate(w.DueDate)
	if err != nil {
		return Task{}, err
	}
	return Task{
		ID: *w.ID, Title: *w.Title, Notes: *w.Notes, Priority: *w.Priority, Done: *w.Done, DueDate: due,
	}, nil
}

// decodeSingle decodes exactly one JSON value and rejects trailing data. Every failure (syntax,
// type mismatch, read error, body over the size limit) maps to ErrMalformed.
func decodeSingle(r io.Reader, v any) error {
	dec := json.NewDecoder(r)
	if err := dec.Decode(v); err != nil {
		return ErrMalformed
	}
	if _, err := dec.Token(); !errors.Is(err, io.EOF) {
		return ErrMalformed
	}
	return nil
}

func decodeDueDate(raw json.RawMessage) (*string, error) {
	if len(raw) == 0 || bytes.Equal(raw, []byte("null")) {
		return nil, nil
	}
	var s string
	if err := json.Unmarshal(raw, &s); err != nil {
		return nil, ErrMalformed
	}
	return &s, nil
}
