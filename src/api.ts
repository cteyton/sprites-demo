export type Status = "todo" | "in_progress" | "done";

export interface Task {
  id: number;
  name: string;
  description: string;
  status: Status;
  position: number;
  created_at: string;
}

async function handle<T>(res: Response): Promise<T> {
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error(body.error || `HTTP ${res.status}`);
  }
  if (res.status === 204) return undefined as T;
  return res.json();
}

export const api = {
  list: () => fetch("/api/tasks").then(handle<Task[]>),
  create: (name: string, description: string) =>
    fetch("/api/tasks", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name, description }),
    }).then(handle<Task>),
  update: (id: number, patch: Partial<Pick<Task, "name" | "description" | "status" | "position">>) =>
    fetch(`/api/tasks/${id}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(patch),
    }).then(handle<Task>),
  remove: (id: number) =>
    fetch(`/api/tasks/${id}`, { method: "DELETE" }).then(handle<void>),
};
