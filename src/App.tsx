import { useEffect, useState } from "react";
import { DndContext, PointerSensor, useSensor, useSensors, type DragEndEvent } from "@dnd-kit/core";
import { api, type Status, type Task } from "./api";
import { Column } from "./components/Column";
import { TaskForm } from "./components/TaskForm";
import { ThemeToggle, type Theme } from "./components/ThemeToggle";

const COLUMNS: { id: Status; title: string }[] = [
  { id: "todo", title: "To-Do" },
  { id: "in_progress", title: "In Progress" },
  { id: "done", title: "Done" },
];

function initialTheme(): Theme {
  if (typeof document !== "undefined" && document.documentElement.classList.contains("dark")) {
    return "dark";
  }
  return "light";
}

export function App() {
  const [tasks, setTasks] = useState<Task[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [theme, setTheme] = useState<Theme>(initialTheme);
  const sensors = useSensors(useSensor(PointerSensor, { activationConstraint: { distance: 5 } }));

  useEffect(() => {
    api.list().then(setTasks).catch((e) => setError(e.message));
  }, []);

  useEffect(() => {
    const root = document.documentElement;
    if (theme === "dark") root.classList.add("dark");
    else root.classList.remove("dark");
    try {
      localStorage.setItem("theme", theme);
    } catch {}
  }, [theme]);

  async function createTask(name: string, description: string) {
    try {
      const task = await api.create(name, description);
      setTasks((prev) => [...prev, task]);
    } catch (e) {
      setError((e as Error).message);
    }
  }

  async function updateTask(id: number, patch: Partial<Pick<Task, "name" | "description" | "status" | "position">>) {
    const prev = tasks;
    setTasks((cur) => cur.map((t) => (t.id === id ? { ...t, ...patch } as Task : t)));
    try {
      const updated = await api.update(id, patch);
      setTasks((cur) => cur.map((t) => (t.id === id ? updated : t)));
    } catch (e) {
      setTasks(prev);
      setError((e as Error).message);
    }
  }

  async function deleteTask(id: number) {
    const prev = tasks;
    setTasks((cur) => cur.filter((t) => t.id !== id));
    try {
      await api.remove(id);
    } catch (e) {
      setTasks(prev);
      setError((e as Error).message);
    }
  }

  function handleDragEnd(event: DragEndEvent) {
    const { active, over } = event;
    if (!over) return;
    const taskId = Number(active.id);
    const newStatus = over.id as Status;
    const task = tasks.find((t) => t.id === taskId);
    if (!task || task.status === newStatus) return;
    updateTask(taskId, { status: newStatus });
  }

  return (
    <div className="min-h-screen flex flex-col">
      <div className="flex-1 p-6 max-w-7xl mx-auto w-full">
        <header className="mb-6 flex items-start justify-between gap-4">
          <div>
            <h1 className="text-3xl font-bold text-black dark:text-white">Wapati Todo</h1>
            <p className="text-sm text-slate-500 dark:text-slate-400 mt-1">Drag cards between columns. SQLite + Bun + React.</p>
          </div>
          <ThemeToggle theme={theme} onChange={setTheme} />
        </header>

        <TaskForm onCreate={createTask} />

        {error && (
          <div className="mb-4 rounded-md border border-red-300 dark:border-red-700 bg-red-50 dark:bg-red-950 text-red-700 dark:text-red-300 px-4 py-2 text-sm flex justify-between items-center">
            <span>{error}</span>
            <button onClick={() => setError(null)} className="text-red-500 hover:text-red-700 dark:hover:text-red-200">×</button>
          </div>
        )}

        <DndContext sensors={sensors} onDragEnd={handleDragEnd}>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            {COLUMNS.map((col) => (
              <Column
                key={col.id}
                id={col.id}
                title={col.title}
                tasks={tasks.filter((t) => t.status === col.id)}
                onUpdate={updateTask}
                onDelete={deleteTask}
              />
            ))}
          </div>
        </DndContext>
      </div>

      <footer className="bg-slate-200 dark:bg-slate-800 px-6 py-4 flex items-center justify-end">
        <p className="text-sm text-slate-600 dark:text-slate-300">Made from Bordeaux with Love - 2026</p>
      </footer>
    </div>
  );
}
