package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"net/url"

	"github.com/motorbit/livecodding/backend/internal/task"

	_ "modernc.org/sqlite" // Pure-Go driver, registered as "sqlite".
)

// SQLite is a Store backed by a SQLite file. Insertion order is kept by the seq column.
type SQLite struct {
	db *sql.DB
}

var schema = []string{`
CREATE TABLE IF NOT EXISTS tasks (
	seq      INTEGER PRIMARY KEY AUTOINCREMENT,
	id       TEXT    NOT NULL UNIQUE,
	title    TEXT    NOT NULL,
	notes    TEXT    NOT NULL,
	priority TEXT    NOT NULL,
	done     INTEGER NOT NULL,
	due_date TEXT
)`, `
CREATE TABLE IF NOT EXISTS idempotency_keys (
	key     TEXT PRIMARY KEY,
	task_id TEXT NOT NULL
)`,
}

// OpenSQLite opens (or creates) the database at path, creates the schema and inserts seeds when
// the tasks table is empty.
func OpenSQLite(ctx context.Context, path string, seeds []task.Task) (*SQLite, error) {
	dsn := "file:" + (&url.URL{Path: path}).EscapedPath() +
		"?_pragma=busy_timeout(5000)&_pragma=journal_mode(WAL)&_pragma=synchronous(NORMAL)"
	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, fmt.Errorf("open sqlite: %w", err)
	}
	// SQLite allows one writer; a single connection avoids SQLITE_BUSY under concurrent requests.
	db.SetMaxOpenConns(1)
	s := &SQLite{db: db}
	if err := s.init(ctx, seeds); err != nil {
		_ = db.Close()
		return nil, err
	}
	return s, nil
}

func (s *SQLite) init(ctx context.Context, seeds []task.Task) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin init: %w", err)
	}
	defer func() { _ = tx.Rollback() }()
	for _, stmt := range schema {
		if _, err := tx.ExecContext(ctx, stmt); err != nil {
			return fmt.Errorf("create schema: %w", err)
		}
	}
	var n int
	if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM tasks`).Scan(&n); err != nil {
		return fmt.Errorf("count tasks: %w", err)
	}
	if n == 0 {
		for _, t := range seeds {
			if err := insert(ctx, tx, t); err != nil {
				return fmt.Errorf("seed: %w", err)
			}
		}
	}
	return tx.Commit()
}

type execer interface {
	ExecContext(ctx context.Context, query string, args ...any) (sql.Result, error)
}

func insert(ctx context.Context, db execer, t task.Task) error {
	_, err := db.ExecContext(ctx,
		`INSERT INTO tasks (id, title, notes, priority, done, due_date) VALUES (?, ?, ?, ?, ?, ?)`,
		t.ID, t.Title, t.Notes, string(t.Priority), t.Done, t.DueDate)
	return err
}

const selectTask = `SELECT id, title, notes, priority, done, due_date FROM tasks`

func scanTask(row interface{ Scan(dest ...any) error }) (task.Task, error) {
	var t task.Task
	var priority string
	var due sql.NullString
	if err := row.Scan(&t.ID, &t.Title, &t.Notes, &priority, &t.Done, &due); err != nil {
		return task.Task{}, err
	}
	t.Priority = task.Priority(priority)
	if due.Valid {
		t.DueDate = &due.String
	}
	return t, nil
}

func (s *SQLite) List(ctx context.Context) ([]task.Task, error) {
	rows, err := s.db.QueryContext(ctx, selectTask+` ORDER BY seq`)
	if err != nil {
		return nil, fmt.Errorf("list tasks: %w", err)
	}
	defer rows.Close()
	out := []task.Task{}
	for rows.Next() {
		t, err := scanTask(rows)
		if err != nil {
			return nil, fmt.Errorf("scan task: %w", err)
		}
		out = append(out, t)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("list tasks: %w", err)
	}
	return out, nil
}

func (s *SQLite) Create(ctx context.Context, t task.Task) (task.Task, error) {
	if err := insert(ctx, s.db, t); err != nil {
		return task.Task{}, fmt.Errorf("create task: %w", err)
	}
	return t, nil
}

func (s *SQLite) CreateOnce(ctx context.Context, key string, t task.Task) (task.Task, bool, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return task.Task{}, false, fmt.Errorf("begin create: %w", err)
	}
	defer func() { _ = tx.Rollback() }()
	var id string
	err = tx.QueryRowContext(ctx, `SELECT task_id FROM idempotency_keys WHERE key = ?`, key).Scan(&id)
	switch {
	case err == nil:
		stored, err := scanTask(tx.QueryRowContext(ctx, selectTask+` WHERE id = ?`, id))
		if errors.Is(err, sql.ErrNoRows) {
			return task.Task{}, false, ErrNotFound
		}
		if err != nil {
			return task.Task{}, false, fmt.Errorf("read keyed task: %w", err)
		}
		return stored, false, nil
	case !errors.Is(err, sql.ErrNoRows):
		return task.Task{}, false, fmt.Errorf("read idempotency key: %w", err)
	}
	if err := insert(ctx, tx, t); err != nil {
		return task.Task{}, false, fmt.Errorf("create task: %w", err)
	}
	if _, err := tx.ExecContext(ctx,
		`INSERT INTO idempotency_keys (key, task_id) VALUES (?, ?)`, key, t.ID); err != nil {
		return task.Task{}, false, fmt.Errorf("store idempotency key: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return task.Task{}, false, fmt.Errorf("commit create: %w", err)
	}
	return t, true, nil
}

func (s *SQLite) Update(ctx context.Context, t task.Task) (task.Task, error) {
	res, err := s.db.ExecContext(ctx,
		`UPDATE tasks SET title = ?, notes = ?, priority = ?, done = ?, due_date = ? WHERE id = ?`,
		t.Title, t.Notes, string(t.Priority), t.Done, t.DueDate, t.ID)
	if err != nil {
		return task.Task{}, fmt.Errorf("update task: %w", err)
	}
	if err := requireOneRow(res); err != nil {
		return task.Task{}, err
	}
	return t, nil
}

func (s *SQLite) Delete(ctx context.Context, id string) error {
	res, err := s.db.ExecContext(ctx, `DELETE FROM tasks WHERE id = ?`, id)
	if err != nil {
		return fmt.Errorf("delete task: %w", err)
	}
	return requireOneRow(res)
}

func (s *SQLite) Close() error { return s.db.Close() }

func requireOneRow(res sql.Result) error {
	n, err := res.RowsAffected()
	if err != nil {
		return fmt.Errorf("rows affected: %w", err)
	}
	if n == 0 {
		return ErrNotFound
	}
	return nil
}

var (
	_ Store = (*SQLite)(nil)
	_ Store = (*Memory)(nil)
)
