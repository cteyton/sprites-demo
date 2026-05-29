import { useDroppable } from "@dnd-kit/core";
import type { Status, Task } from "../api";
import { TaskCard } from "./TaskCard";

interface Props {
  id: Status;
  title: string;
  tasks: Task[];
  onUpdate: (id: number, patch: Partial<Pick<Task, "name" | "description" | "status" | "severity">>) => void;
  onDelete: (id: number) => void;
  onOpenDrawer: (id: number) => void;
}

const COLUMN_ACCENT: Record<Status, string> = {
  todo: "bg-slate-100 text-slate-700 dark:bg-slate-800 dark:text-slate-200",
  in_progress: "bg-blue-100 text-blue-700 dark:bg-blue-900/60 dark:text-blue-200",
  done: "bg-green-100 text-green-700 dark:bg-green-900/60 dark:text-green-200",
};

export function Column({ id, title, tasks, onDelete, onOpenDrawer }: Props) {
  const { setNodeRef, isOver } = useDroppable({ id });

  return (
    <div
      ref={setNodeRef}
      className={`rounded-lg bg-white dark:bg-slate-900 shadow-sm border border-slate-200 dark:border-slate-700 flex flex-col min-h-[400px] transition-colors ${
        isOver ? "border-blue-400 bg-blue-50/50 dark:border-blue-400 dark:bg-blue-950/30" : ""
      }`}
    >
      <header className="px-4 py-3 border-b border-slate-200 dark:border-slate-700 flex justify-between items-center">
        <h2 className="font-semibold text-slate-700 dark:text-slate-100">{title}</h2>
        <span className={`text-xs px-2 py-0.5 rounded-full ${COLUMN_ACCENT[id]}`}>{tasks.length}</span>
      </header>
      <div className="p-3 flex flex-col gap-2 flex-1">
        {tasks.length === 0 && (
          <p className="text-xs text-slate-400 dark:text-slate-500 text-center py-4">No tasks</p>
        )}
        {tasks.map((task) => (
          <TaskCard key={task.id} task={task} onDelete={onDelete} onOpenDrawer={onOpenDrawer} />
        ))}
      </div>
    </div>
  );
}
