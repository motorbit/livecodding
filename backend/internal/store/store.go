// Package store persists tasks. Every implementation keeps insertion order.
package store

import (
	"context"
	_ "embed"
	"encoding/json"
	"errors"
	"fmt"

	"github.com/motorbit/livecodding/backend/internal/task"
)

// ErrNotFound is returned by Update and Delete for an unknown id.
var ErrNotFound = errors.New("task not found")

// ErrVersionMismatch is returned by Update and Delete when ifVersion is set and differs from the
// stored version.
var ErrVersionMismatch = errors.New("task version mismatch")

// AnyVersion makes Update and Delete unconditional.
const AnyVersion = 0

// Store is the task repository. IDs are canonical (see task.ParseID); callers validate tasks
// before storing them.
type Store interface {
	// List returns all tasks in insertion order.
	List(ctx context.Context) ([]task.Task, error)
	// Create appends t, which must carry a new id, with version 1.
	Create(ctx context.Context, t task.Task) (task.Task, error)
	// CreateOnce is Create keyed by an idempotency key. The first call with a key appends t and
	// returns created == true. Later calls with the same key append nothing and return the task
	// the key created, as it is now, or ErrNotFound if it has been deleted since.
	CreateOnce(ctx context.Context, key string, t task.Task) (stored task.Task, created bool, err error)
	// Update replaces the task with t.ID in place, keeping its position, and increments its
	// version (t.Version is ignored). Unless ifVersion is AnyVersion, the stored version must
	// equal it.
	Update(ctx context.Context, t task.Task, ifVersion int) (task.Task, error)
	// Delete removes the task with the given id. Unless ifVersion is AnyVersion, the stored
	// version must equal it.
	Delete(ctx context.Context, id string, ifVersion int) error
	// Close releases resources.
	Close() error
}

// seedJSON is a byte-identical copy of Modules/Sources/TaskClient/Resources/seed-tasks.json
// (enforced by TestSeedFileMatchesIOSBundle).
//
//go:embed seed-tasks.json
var seedJSON []byte

type seedTask struct {
	Title    string        `json:"title"`
	Notes    string        `json:"notes"`
	Priority task.Priority `json:"priority"`
	Done     bool          `json:"done"`
}

// Seeds returns the challenge tasks in file order with stable ids
// 00000000-0000-0000-0000-00000000000N (1-based) and no due date, like MockNetworkClient.
func Seeds() []task.Task {
	var raw []seedTask
	if err := json.Unmarshal(seedJSON, &raw); err != nil {
		panic(fmt.Sprintf("store: embedded seed-tasks.json is malformed: %v", err))
	}
	out := make([]task.Task, len(raw))
	for i, s := range raw {
		out[i] = task.Task{
			ID:       fmt.Sprintf("00000000-0000-0000-0000-%012d", i+1),
			Title:    s.Title,
			Notes:    s.Notes,
			Priority: s.Priority,
			Done:     s.Done,
			Version:  1,
		}
	}
	return out
}
