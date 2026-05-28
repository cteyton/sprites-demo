import { Database } from "bun:sqlite";

export type Status = "todo" | "in_progress" | "done";

export interface Task {
  id: number;
  name: string;
  description: string;
  status: Status;
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
    position INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  );
`);

export const queries = {
  list: db.query<Task, []>("SELECT * FROM tasks ORDER BY status, position, id"),
  get: db.query<Task, { $id: number }>("SELECT * FROM tasks WHERE id = $id"),
  insert: db.query<Task, { $name: string; $description: string; $position: number }>(
    "INSERT INTO tasks (name, description, position) VALUES ($name, $description, $position) RETURNING *",
  ),
  update: db.query<Task, { $id: number; $name: string; $description: string; $status: Status; $position: number }>(
    "UPDATE tasks SET name = $name, description = $description, status = $status, position = $position WHERE id = $id RETURNING *",
  ),
  remove: db.query("DELETE FROM tasks WHERE id = $id"),
  maxPosition: db.query<{ max: number | null }, { $status: Status }>(
    "SELECT COALESCE(MAX(position), -1) AS max FROM tasks WHERE status = $status",
  ),
};

export default db;
