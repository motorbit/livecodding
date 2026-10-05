// Package task holds the Task Board domain model and its wire (JSON) shape.
//
// The JSON shape mirrors the iOS DTOs in Modules/Sources/TaskClient/TaskDTO.swift:
// TaskDTO, TaskDraftDTO and PriorityDTO.
package task

import (
	"errors"
	"strings"
	"time"
	"unicode"
)

// Priority mirrors PriorityDTO. The raw values are case-sensitive.
type Priority string

const (
	PriorityLow    Priority = "Low"
	PriorityMedium Priority = "Medium"
	PriorityHigh   Priority = "High"
)

// Valid reports whether p is one of Low, Medium or High.
func (p Priority) Valid() bool {
	switch p {
	case PriorityLow, PriorityMedium, PriorityHigh:
		return true
	}
	return false
}

// Task mirrors TaskDTO. DueDate is a UTC calendar day ("yyyy-MM-dd"), omitted when nil.
type Task struct {
	ID       string   `json:"id"`
	Title    string   `json:"title"`
	Notes    string   `json:"notes"`
	Priority Priority `json:"priority"`
	Done     bool     `json:"done"`
	DueDate  *string  `json:"due_date,omitempty"`
}

// Draft mirrors TaskDraftDTO, the POST /tasks body.
type Draft struct {
	Title    string
	Notes    string
	Priority Priority
	DueDate  *string
}

// DueDateLayout is the wire format of due_date.
const DueDateLayout = "2006-01-02"

// Validation errors. Messages are short and never contain user input.
var (
	ErrEmptyTitle      = errors.New("title must not be empty")
	ErrInvalidPriority = errors.New("priority must be Low, Medium or High")
	ErrInvalidDueDate  = errors.New("due_date must be a yyyy-MM-dd date")
)

// NormalizeTitle trims whitespace and newlines (like Swift's .whitespacesAndNewlines) and rejects
// an empty result.
func NormalizeTitle(title string) (string, error) {
	trimmed := strings.TrimFunc(title, unicode.IsSpace)
	if trimmed == "" {
		return "", ErrEmptyTitle
	}
	return trimmed, nil
}

// ValidateDueDate accepts nil or a strict, existing yyyy-MM-dd date.
func ValidateDueDate(due *string) error {
	if due == nil {
		return nil
	}
	if len(*due) != len(DueDateLayout) {
		return ErrInvalidDueDate
	}
	if _, err := time.Parse(DueDateLayout, *due); err != nil {
		return ErrInvalidDueDate
	}
	return nil
}

// NewFromDraft validates d and returns a not-done task with the given id and a trimmed title.
func NewFromDraft(id string, d Draft) (Task, error) {
	t := Task{ID: id, Title: d.Title, Notes: d.Notes, Priority: d.Priority, DueDate: d.DueDate}
	return Normalize(t)
}

// Normalize validates t and returns it with a trimmed title.
func Normalize(t Task) (Task, error) {
	title, err := NormalizeTitle(t.Title)
	if err != nil {
		return Task{}, err
	}
	if !t.Priority.Valid() {
		return Task{}, ErrInvalidPriority
	}
	if err := ValidateDueDate(t.DueDate); err != nil {
		return Task{}, err
	}
	t.Title = title
	return t, nil
}
