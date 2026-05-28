import { useState } from "react";
import { useDraggable } from "@dnd-kit/core";
import { CSS } from "@dnd-kit/utilities";
import type { Task } from "../api";

const MAX_DESC = 500;

interface Props {
  task: Task;
  onUpdate: (id: number, patch: Partial<Pick<Task, "name" | "description" | "status">>) => void;
  onDelete: (id: number) => void;
}

export function TaskCard({ task, onUpdate, onDelete }: Props) {
  const [editing, setEditing] = useState(false);
  const [name, setName] = useState(task.name);
  const [description, setDescription] = useState(task.description);

  const { attributes, listeners, setNodeRef, transform, isDragging } = useDraggable({
    id: task.id,
    disabled: editing,
  });

  const style = {
    transform: CSS.Translate.toString(transform),
    opacity: isDragging ? 0.4 : 1,
  };

  function save() {
    const trimmed = name.trim();
    if (!trimmed) return;
    onUpdate(task.id, { name: trimmed, description });
    setEditing(false);
  }

  function cancel() {
    setName(task.name);
    setDescription(task.description);
    setEditing(false);
  }

  if (editing) {
    return (
      <div className="rounded-md border border-blue-300 bg-white p-3 shadow-sm">
        <input
          value={name}
          onChange={(e) => setName(e.target.value)}
          maxLength={200}
          className="w-full border border-slate-300 rounded px-2 py-1 text-sm font-medium mb-2 focus:outline-none focus:ring-1 focus:ring-blue-400"
          autoFocus
        />
        <textarea
          value={description}
          onChange={(e) => setDescription(e.target.value.slice(0, MAX_DESC))}
          rows={3}
          className="w-full border border-slate-300 rounded px-2 py-1 text-xs resize-y focus:outline-none focus:ring-1 focus:ring-blue-400"
          placeholder="Description (max 500 chars)"
        />
        <div className="flex justify-between items-center mt-2">
          <span className="text-[10px] text-slate-400">{description.length}/{MAX_DESC}</span>
          <div className="flex gap-1">
            <button onClick={cancel} className="text-xs px-2 py-1 rounded hover:bg-slate-100 text-slate-600">Cancel</button>
            <button onClick={save} className="text-xs px-2 py-1 rounded bg-blue-600 text-white hover:bg-blue-700">Save</button>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div
      ref={setNodeRef}
      style={style}
      {...listeners}
      {...attributes}
      className="rounded-md border border-slate-200 bg-white p-3 shadow-sm hover:shadow-md cursor-grab active:cursor-grabbing select-none"
    >
      <div className="flex justify-between items-start gap-2">
        <h3 className="font-medium text-sm text-slate-800 break-words flex-1">{task.name}</h3>
        <div className="flex gap-1 shrink-0">
          <button
            onPointerDown={(e) => e.stopPropagation()}
            onClick={() => setEditing(true)}
            className="text-xs text-slate-400 hover:text-slate-700 px-1"
            title="Edit"
          >
            ✎
          </button>
          <button
            onPointerDown={(e) => e.stopPropagation()}
            onClick={() => onDelete(task.id)}
            className="text-xs text-slate-400 hover:text-red-600 px-1"
            title="Delete"
          >
            ✕
          </button>
        </div>
      </div>
      {task.description && (
        <p className="text-xs text-slate-500 mt-1 break-words whitespace-pre-wrap">{task.description}</p>
      )}
    </div>
  );
}
