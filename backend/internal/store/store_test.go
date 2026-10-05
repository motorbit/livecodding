package store

import (
	"bytes"
	"context"
	"errors"
	"os"
	"path/filepath"
	"slices"
	"testing"

	"github.com/motorbit/livecodding/backend/internal/task"
)

func ptr(s string) *string { return &s }

func TestSeedFileMatchesIOSBundle(t *testing.T) {
	ios, err := os.ReadFile(filepath.Join("..", "..", "..", "Modules", "Sources", "TaskClient", "Resources", "seed-tasks.json"))
	if err != nil {
		t.Fatalf("read iOS seed file: %v", err)
	}
	if !bytes.Equal(ios, seedJSON) {
		t.Fatal("internal/store/seed-tasks.json drifted from Modules/Sources/TaskClient/Resources/seed-tasks.json; copy it over")
	}
}

func TestSeeds(t *testing.T) {
	seeds := Seeds()
	if len(seeds) != 4 {
		t.Fatalf("len(Seeds()) = %d, want 4", len(seeds))
	}
	want := []string{
		"00000000-0000-0000-0000-000000000001", "00000000-0000-0000-0000-000000000002",
		"00000000-0000-0000-0000-000000000003", "00000000-0000-0000-0000-000000000004",
	}
	for i, s := range seeds {
		if s.ID != want[i] || s.DueDate != nil {
			t.Errorf("seed %d = %+v", i, s)
		}
		if _, err := task.Normalize(s); err != nil {
			t.Errorf("seed %d invalid: %v", i, err)
		}
	}
	if seeds[0].Title != "Renew domain registration" || seeds[0].Priority != task.PriorityHigh || !seeds[2].Done {
		t.Errorf("seed content mismatch: %+v", seeds)
	}
}

// factory opens a store on seeds. dir is a per-test temp dir that factories may use.
type factory func(t *testing.T, dir string, seeds []task.Task) Store

func factories() map[string]factory {
	return map[string]factory{
		"memory": func(_ *testing.T, _ string, seeds []task.Task) Store { return NewMemory(seeds) },
		"sqlite": func(t *testing.T, dir string, seeds []task.Task) Store {
			s, err := OpenSQLite(context.Background(), filepath.Join(dir, "tasks.db"), seeds)
			if err != nil {
				t.Fatalf("OpenSQLite: %v", err)
			}
			return s
		},
	}
}

func ids(tasks []task.Task) []string {
	out := make([]string, len(tasks))
	for i, t := range tasks {
		out[i] = t.ID
	}
	return out
}

func mustList(t *testing.T, s Store) []task.Task {
	t.Helper()
	got, err := s.List(context.Background())
	if err != nil {
		t.Fatalf("List: %v", err)
	}
	return got
}

func TestStoreContract(t *testing.T) {
	ctx := context.Background()
	newTask := func(id, title string) task.Task {
		return task.Task{ID: id, Title: title, Notes: "", Priority: task.PriorityMedium}
	}
	idA, idB, idC := task.NewID(), task.NewID(), task.NewID()

	cases := []struct {
		name string
		run  func(t *testing.T, s Store)
	}{
		{"list returns seeds in order", func(t *testing.T, s Store) {
			if got := mustList(t, s); !slices.Equal(ids(got), ids(Seeds())) {
				t.Fatalf("ids = %v", ids(got))
			}
			if got := mustList(t, s); !slices.EqualFunc(got, Seeds(), equalTask) {
				t.Fatalf("tasks = %+v", got)
			}
		}},
		{"create appends in insertion order", func(t *testing.T, s Store) {
			// Titles deliberately sort differently from insertion order.
			for _, tk := range []task.Task{newTask(idA, "Zulu"), newTask(idB, "Alpha"), newTask(idC, "Mike")} {
				if got, err := s.Create(ctx, tk); err != nil || !equalTask(got, tk) {
					t.Fatalf("Create = %+v, %v", got, err)
				}
			}
			got := ids(mustList(t, s))
			want := append(ids(Seeds()), idA, idB, idC)
			if !slices.Equal(got, want) {
				t.Fatalf("ids = %v, want %v", got, want)
			}
		}},
		{"create rejects a duplicate id", func(t *testing.T, s Store) {
			if _, err := s.Create(ctx, newTask(Seeds()[0].ID, "dup")); err == nil {
				t.Fatal("Create duplicate: want error")
			}
		}},
		{"update replaces in place and keeps position", func(t *testing.T, s Store) {
			upd := Seeds()[1]
			upd.Title, upd.Notes, upd.Done, upd.Priority, upd.DueDate = "New", "N", true, task.PriorityHigh, ptr("2026-12-31")
			if got, err := s.Update(ctx, upd); err != nil || !equalTask(got, upd) {
				t.Fatalf("Update = %+v, %v", got, err)
			}
			list := mustList(t, s)
			if !slices.Equal(ids(list), ids(Seeds())) || !equalTask(list[1], upd) {
				t.Fatalf("after update = %+v", list)
			}
			upd.DueDate = nil
			if _, err := s.Update(ctx, upd); err != nil {
				t.Fatal(err)
			}
			if got := mustList(t, s)[1]; got.DueDate != nil {
				t.Fatalf("due date not cleared: %+v", got)
			}
		}},
		{"update unknown id is not found", func(t *testing.T, s Store) {
			if _, err := s.Update(ctx, newTask(idA, "x")); !errors.Is(err, ErrNotFound) {
				t.Fatalf("err = %v, want ErrNotFound", err)
			}
		}},
		{"delete removes and keeps order", func(t *testing.T, s Store) {
			if err := s.Delete(ctx, Seeds()[1].ID); err != nil {
				t.Fatal(err)
			}
			want := []string{Seeds()[0].ID, Seeds()[2].ID, Seeds()[3].ID}
			if got := ids(mustList(t, s)); !slices.Equal(got, want) {
				t.Fatalf("ids = %v, want %v", got, want)
			}
			if err := s.Delete(ctx, Seeds()[1].ID); !errors.Is(err, ErrNotFound) {
				t.Fatalf("second delete err = %v, want ErrNotFound", err)
			}
		}},
		{"delete unknown id is not found", func(t *testing.T, s Store) {
			if err := s.Delete(ctx, idA); !errors.Is(err, ErrNotFound) {
				t.Fatalf("err = %v, want ErrNotFound", err)
			}
		}},
		{"list of an empty store is an empty slice", func(t *testing.T, s Store) {
			for _, sd := range Seeds() {
				if err := s.Delete(ctx, sd.ID); err != nil {
					t.Fatal(err)
				}
			}
			if got := mustList(t, s); got == nil || len(got) != 0 {
				t.Fatalf("List = %#v, want empty non-nil", got)
			}
		}},
		{"returned tasks don't alias stored state", func(t *testing.T, s Store) {
			tk := newTask(idA, "x")
			tk.DueDate = ptr("2026-01-01")
			if _, err := s.Create(ctx, tk); err != nil {
				t.Fatal(err)
			}
			*tk.DueDate = "1999-01-01"
			list := mustList(t, s)
			*list[len(list)-1].DueDate = "1999-01-01"
			if got := mustList(t, s)[len(list)-1]; *got.DueDate != "2026-01-01" {
				t.Fatalf("stored due date mutated: %v", *got.DueDate)
			}
		}},
	}

	for name, open := range factories() {
		t.Run(name, func(t *testing.T) {
			for _, tc := range cases {
				t.Run(tc.name, func(t *testing.T) {
					s := open(t, t.TempDir(), Seeds())
					t.Cleanup(func() { _ = s.Close() })
					tc.run(t, s)
				})
			}
		})
	}
}

func TestSQLitePersistsAcrossReopen(t *testing.T) {
	ctx := context.Background()
	path := filepath.Join(t.TempDir(), "tasks.db")
	s, err := OpenSQLite(ctx, path, Seeds())
	if err != nil {
		t.Fatal(err)
	}
	created := task.Task{ID: task.NewID(), Title: "Persist me", Priority: task.PriorityLow, DueDate: ptr("2026-10-05")}
	if _, err := s.Create(ctx, created); err != nil {
		t.Fatal(err)
	}
	if err := s.Delete(ctx, Seeds()[0].ID); err != nil {
		t.Fatal(err)
	}
	want := mustList(t, s)
	if err := s.Close(); err != nil {
		t.Fatal(err)
	}

	reopened, err := OpenSQLite(ctx, path, Seeds())
	if err != nil {
		t.Fatal(err)
	}
	defer reopened.Close()
	got := mustList(t, reopened)
	if !slices.EqualFunc(got, want, equalTask) {
		t.Fatalf("after reopen = %+v, want %+v (seeds must not be re-inserted)", got, want)
	}
}

func TestSQLiteSeedsOnlyEmptyTable(t *testing.T) {
	ctx := context.Background()
	path := filepath.Join(t.TempDir(), "tasks.db")
	s, err := OpenSQLite(ctx, path, nil)
	if err != nil {
		t.Fatal(err)
	}
	if got := mustList(t, s); len(got) != 0 {
		t.Fatalf("no seeds: got %d tasks", len(got))
	}
	_ = s.Close()
	s, err = OpenSQLite(ctx, path, Seeds())
	if err != nil {
		t.Fatal(err)
	}
	defer s.Close()
	if got := mustList(t, s); len(got) != len(Seeds()) {
		t.Fatalf("empty table should be seeded: got %d tasks", len(got))
	}
}

func equalTask(a, b task.Task) bool {
	if (a.DueDate == nil) != (b.DueDate == nil) || (a.DueDate != nil && *a.DueDate != *b.DueDate) {
		return false
	}
	a.DueDate, b.DueDate = nil, nil
	return a == b
}
