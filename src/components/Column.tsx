import { useDroppable } from "@dnd-kit/core";
import type { Status, Task } from "../api";
import { TaskCard } from "./TaskCard";

interface Props {
  id: Status;
  title: string;
  tasks: Task[];
  onUpdate: (id: number, patch: Partial<Pick<Task, "name" | "description" | "status">>) => void;
  onDelete: (id: number) => void;
}

export function Column({ id, title, tasks, onUpdate, onDelete }: Props) {
  const { setNodeRef, isOver } = useDroppable({ id });

  return (
    <div
      ref={setNodeRef}
      className={`rounded-lg bg-white shadow-sm border border-slate-200 flex flex-col min-h-[400px] transition-colors ${
        isOver ? "border-blue-400 bg-blue-50/50" : ""
      }`}
    >
      <header className="px-4 py-3 border-b border-slate-200 flex justify-between items-center">
        <h2 className="font-semibold text-slate-700">{title}</h2>
        <span className="text-xs px-2 py-0.5 rounded-full bg-slate-100 text-slate-600">{tasks.length}</span>
      </header>
      <div className="p-3 flex flex-col gap-2 flex-1">
        {tasks.length === 0 && <p className="text-xs text-slate-400 text-center py-4">No tasks</p>}
        {tasks.map((task) => (
          <TaskCard key={task.id} task={task} onUpdate={onUpdate} onDelete={onDelete} />
        ))}
      </div>
    </div>
  );
}
