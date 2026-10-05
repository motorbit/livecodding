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
}

// NewMemory returns a Memory store holding a copy of seeds.
func NewMemory(seeds []task.Task) *Memory {
	m := &Memory{tasks: make([]task.Task, 0, len(seeds))}
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
	m.tasks = append(m.tasks, clone(t))
	return clone(t), nil
}

func (m *Memory) Update(_ context.Context, t task.Task) (task.Task, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	i := m.index(t.ID)
	if i < 0 {
		return task.Task{}, ErrNotFound
	}
	m.tasks[i] = clone(t)
	return clone(t), nil
}

func (m *Memory) Delete(_ context.Context, id string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	i := m.index(id)
	if i < 0 {
		return ErrNotFound
	}
	m.tasks = slices.Delete(m.tasks, i, i+1)
	return nil
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
