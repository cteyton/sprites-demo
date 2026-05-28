import { useState } from "react";

const MAX_DESC = 500;
const MAX_NAME = 200;

interface Props {
  onCreate: (name: string, description: string) => void;
}

export function TaskForm({ onCreate }: Props) {
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [expanded, setExpanded] = useState(false);

  function submit(e: React.FormEvent) {
    e.preventDefault();
    const trimmed = name.trim();
    if (!trimmed) return;
    onCreate(trimmed, description);
    setName("");
    setDescription("");
    setExpanded(false);
  }

  return (
    <form onSubmit={submit} className="mb-6 bg-white rounded-lg border border-slate-200 p-3 shadow-sm">
      <div className="flex gap-2">
        <input
          value={name}
          onChange={(e) => setName(e.target.value)}
          onFocus={() => setExpanded(true)}
          maxLength={MAX_NAME}
          placeholder="New task name…"
          className="flex-1 border border-slate-300 rounded px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-blue-400"
        />
        <button
          type="submit"
          disabled={!name.trim()}
          className="px-4 py-2 rounded bg-blue-600 text-white text-sm font-medium hover:bg-blue-700 disabled:bg-slate-300 disabled:cursor-not-allowed"
        >
          Add
        </button>
      </div>
      {expanded && (
        <div className="mt-2">
          <textarea
            value={description}
            onChange={(e) => setDescription(e.target.value.slice(0, MAX_DESC))}
            rows={2}
            placeholder="Description (optional, max 500 chars)"
            className="w-full border border-slate-300 rounded px-3 py-2 text-sm resize-y focus:outline-none focus:ring-2 focus:ring-blue-400"
          />
          <div className="text-[10px] text-slate-400 text-right mt-1">{description.length}/{MAX_DESC}</div>
        </div>
      )}
    </form>
  );
}
