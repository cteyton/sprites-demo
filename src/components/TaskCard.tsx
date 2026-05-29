import { useDraggable } from "@dnd-kit/core";
import { CSS } from "@dnd-kit/utilities";
import type { Severity, Status, Task } from "../api";

const STATUS_BORDER: Record<Status, string> = {
  todo: "border-slate-800 dark:border-slate-300",
  in_progress: "border-blue-500 dark:border-blue-400",
  done: "border-green-500 dark:border-green-400",
};

const SEVERITY_BADGE: Record<Severity, string> = {
  high: "bg-red-100 text-red-700 dark:bg-red-900/60 dark:text-red-300",
  medium: "bg-yellow-100 text-yellow-700 dark:bg-yellow-900/60 dark:text-yellow-300",
  low: "bg-green-100 text-green-700 dark:bg-green-900/60 dark:text-green-300",
};

interface Props {
  task: Task;
  onDelete: (id: number) => void;
  onOpenDrawer: (id: number) => void;
}

export function TaskCard({ task, onDelete, onOpenDrawer }: Props) {
  const { attributes, listeners, setNodeRef, transform, isDragging } = useDraggable({
    id: task.id,
  });

  const style = {
    transform: CSS.Translate.toString(transform),
    opacity: isDragging ? 0.4 : 1,
  };

  return (
    <div
      ref={setNodeRef}
      style={style}
      {...listeners}
      {...attributes}
      className={`rounded-md border-2 ${STATUS_BORDER[task.status]} bg-white dark:bg-slate-800 p-3 shadow-sm hover:shadow-md cursor-grab active:cursor-grabbing select-none`}
    >
      <div className="flex justify-between items-start gap-2">
        <h3 className="font-medium text-sm text-slate-800 dark:text-slate-100 break-words flex-1">{task.name}</h3>
        <div className="flex gap-1 shrink-0">
          <button
            onPointerDown={(e) => e.stopPropagation()}
            onClick={() => onOpenDrawer(task.id)}
            className="text-xs text-slate-400 dark:text-slate-500 hover:text-slate-700 dark:hover:text-slate-200 px-1"
            title="Edit"
          >
            ✎
          </button>
          <button
            onPointerDown={(e) => e.stopPropagation()}
            onClick={() => onDelete(task.id)}
            className="text-xs text-slate-400 dark:text-slate-500 hover:text-red-600 dark:hover:text-red-400 px-1"
            title="Delete"
          >
            ✕
          </button>
        </div>
      </div>
      {task.description && (
        <p className="text-xs text-slate-500 dark:text-slate-400 mt-1 break-words whitespace-pre-wrap">{task.description}</p>
      )}
      <div className="mt-2">
        <span className={`text-[10px] font-medium px-1.5 py-0.5 rounded ${SEVERITY_BADGE[task.severity]}`}>
          {task.severity}
        </span>
      </div>
    </div>
  );
}
