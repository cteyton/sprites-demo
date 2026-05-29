import { Database } from "bun:sqlite";

export type Status = "todo" | "in_progress" | "done";
export type Severity = "high" | "medium" | "low";

export interface Task {
  id: number;
  name: string;
  description: string;
  status: Status;
  severity: Severity;
  position: number;
  created_at: string;
}

const db = new Database("tasks.sqlite");
db.exec("PRAGMA journal_mode = WAL;");
db.exec(`
  CREATE TABLE IF NOT EXISTS tasks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    description TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL CHECK (status IN ('todo','in_progress','done')) DEFAULT 'todo',
    severity TEXT NOT NULL CHECK (severity IN ('high','medium','low')) DEFAULT 'medium',
    position INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  );
`);

// Migrate existing tables: add severity column if missing
try {
  db.exec("ALTER TABLE tasks ADD COLUMN severity TEXT NOT NULL DEFAULT 'medium' CHECK (severity IN ('high','medium','low'))");
} catch {
  // Column already exists — ignore
}

export const queries = {
  list: db.query<Task, []>("SELECT * FROM tasks ORDER BY status, position, id"),
  get: db.query<Task, { $id: number }>("SELECT * FROM tasks WHERE id = $id"),
  insert: db.query<Task, { $name: string; $description: string; $position: number }>(
    "INSERT INTO tasks (name, description, position) VALUES ($name, $description, $position) RETURNING *",
  ),
  update: db.query<Task, { $id: number; $name: string; $description: string; $status: Status; $severity: Severity; $position: number }>(
    "UPDATE tasks SET name = $name, description = $description, status = $status, severity = $severity, position = $position WHERE id = $id RETURNING *",
  ),
  remove: db.query("DELETE FROM tasks WHERE id = $id"),
  maxPosition: db.query<{ max: number | null }, { $status: Status }>(
    "SELECT COALESCE(MAX(position), -1) AS max FROM tasks WHERE status = $status",
  ),
};

export default db;
