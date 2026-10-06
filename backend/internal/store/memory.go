package store

import (
	"context"
	"fmt"
	"slices"
	"sync"

	"github.com/motorbit/livecodding/backend/internal/task"
)

// Memory is an in-process Store. Data is lost on restart.
type Memory struct {
	mu    sync.RWMutex
	tasks []task.Task
	// keys maps an idempotency key to the id of the task it created.
	keys map[string]string
}

// NewMemory returns a Memory store holding a copy of seeds.
func NewMemory(seeds []task.Task) *Memory {
	m := &Memory{tasks: make([]task.Task, 0, len(seeds)), keys: map[string]string{}}
	for _, t := range seeds {
		m.tasks = append(m.tasks, clone(t))
	}
	return m
}

func (m *Memory) List(_ context.Context) ([]task.Task, error) {
	m.mu.RLock()
	defer m.mu.RUnlock()
	out := make([]task.Task, len(m.tasks))
	for i, t := range m.tasks {
		out[i] = clone(t)
	}
	return out, nil
}

func (m *Memory) Create(_ context.Context, t task.Task) (task.Task, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.index(t.ID) >= 0 {
		return task.Task{}, fmt.Errorf("memory store: duplicate id")
	}
	t.Version = 1
	m.tasks = append(m.tasks, clone(t))
	return clone(t), nil
}

func (m *Memory) CreateOnce(_ context.Context, key string, t task.Task) (task.Task, bool, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if id, ok := m.keys[key]; ok {
		i := m.index(id)
		if i < 0 {
			return task.Task{}, false, ErrNotFound
		}
		return clone(m.tasks[i]), false, nil
	}
	if m.index(t.ID) >= 0 {
		return task.Task{}, false, fmt.Errorf("memory store: duplicate id")
	}
	t.Version = 1
	m.tasks = append(m.tasks, clone(t))
	m.keys[key] = t.ID
	return clone(t), true, nil
}

func (m *Memory) Update(_ context.Context, t task.Task, ifVersion int) (task.Task, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	i, err := m.match(t.ID, ifVersion)
	if err != nil {
		return task.Task{}, err
	}
	t.Version = m.tasks[i].Version + 1
	m.tasks[i] = clone(t)
	return clone(t), nil
}

func (m *Memory) Delete(_ context.Context, id string, ifVersion int) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	i, err := m.match(id, ifVersion)
	if err != nil {
		return err
	}
	m.tasks = slices.Delete(m.tasks, i, i+1)
	return nil
}

// match returns the index of id, checking ifVersion. Callers hold the lock.
func (m *Memory) match(id string, ifVersion int) (int, error) {
	i := m.index(id)
	if i < 0 {
		return -1, ErrNotFound
	}
	if ifVersion != AnyVersion && m.tasks[i].Version != ifVersion {
		return -1, ErrVersionMismatch
	}
	return i, nil
}

func (m *Memory) Close() error { return nil }

func (m *Memory) index(id string) int {
	return slices.IndexFunc(m.tasks, func(t task.Task) bool { return t.ID == id })
}

// clone copies the DueDate pointer target so callers can't mutate stored state.
func clone(t task.Task) task.Task {
	if t.DueDate != nil {
		d := *t.DueDate
		t.DueDate = &d
	}
	return t
}
