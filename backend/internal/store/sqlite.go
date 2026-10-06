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
	due_date TEXT,
	version  INTEGER NOT NULL DEFAULT 1
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
	// Databases created before versioning lack the column; existing tasks start at version 1.
	var hasVersion bool
	if err := tx.QueryRowContext(ctx,
		`SELECT COUNT(*) > 0 FROM pragma_table_info('tasks') WHERE name = 'version'`).Scan(&hasVersion); err != nil {
		return fmt.Errorf("inspect schema: %w", err)
	}
	if !hasVersion {
		if _, err := tx.ExecContext(ctx, `ALTER TABLE tasks ADD COLUMN version INTEGER NOT NULL DEFAULT 1`); err != nil {
			return fmt.Errorf("add version column: %w", err)
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

// insert stores t with version 1.
func insert(ctx context.Context, db execer, t task.Task) error {
	_, err := db.ExecContext(ctx,
		`INSERT INTO tasks (id, title, notes, priority, done, due_date, version) VALUES (?, ?, ?, ?, ?, ?, 1)`,
		t.ID, t.Title, t.Notes, string(t.Priority), t.Done, t.DueDate)
	return err
}

const selectTask = `SELECT id, title, notes, priority, done, due_date, version FROM tasks`

func scanTask(row interface{ Scan(dest ...any) error }) (task.Task, error) {
	var t task.Task
	var priority string
	var due sql.NullString
	if err := row.Scan(&t.ID, &t.Title, &t.Notes, &priority, &t.Done, &due, &t.Version); err != nil {
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
	t.Version = 1
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
	t.Version = 1
	return t, true, nil
}

func (s *SQLite) Update(ctx context.Context, t task.Task, ifVersion int) (task.Task, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return task.Task{}, fmt.Errorf("begin update: %w", err)
	}
	defer func() { _ = tx.Rollback() }()
	current, err := matchVersion(ctx, tx, t.ID, ifVersion)
	if err != nil {
		return task.Task{}, err
	}
	t.Version = current + 1
	if _, err := tx.ExecContext(ctx,
		`UPDATE tasks SET title = ?, notes = ?, priority = ?, done = ?, due_date = ?, version = ? WHERE id = ?`,
		t.Title, t.Notes, string(t.Priority), t.Done, t.DueDate, t.Version, t.ID); err != nil {
		return task.Task{}, fmt.Errorf("update task: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return task.Task{}, fmt.Errorf("commit update: %w", err)
	}
	return t, nil
}

func (s *SQLite) Delete(ctx context.Context, id string, ifVersion int) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin delete: %w", err)
	}
	defer func() { _ = tx.Rollback() }()
	if _, err := matchVersion(ctx, tx, id, ifVersion); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `DELETE FROM tasks WHERE id = ?`, id); err != nil {
		return fmt.Errorf("delete task: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("commit delete: %w", err)
	}
	return nil
}

func (s *SQLite) Close() error { return s.db.Close() }

// matchVersion returns the stored version of id, checking ifVersion.
func matchVersion(ctx context.Context, tx *sql.Tx, id string, ifVersion int) (int, error) {
	var current int
	err := tx.QueryRowContext(ctx, `SELECT version FROM tasks WHERE id = ?`, id).Scan(&current)
	if errors.Is(err, sql.ErrNoRows) {
		return 0, ErrNotFound
	}
	if err != nil {
		return 0, fmt.Errorf("read version: %w", err)
	}
	if ifVersion != AnyVersion && current != ifVersion {
		return 0, ErrVersionMismatch
	}
	return current, nil
}

var (
	_ Store = (*SQLite)(nil)
	_ Store = (*Memory)(nil)
)
