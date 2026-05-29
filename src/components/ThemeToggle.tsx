export type Theme = "light" | "dark";

interface Props {
  theme: Theme;
  onChange: (theme: Theme) => void;
}

export function ThemeToggle({ theme, onChange }: Props) {
  const isDark = theme === "dark";
  const next: Theme = isDark ? "light" : "dark";

  return (
    <button
      type="button"
      role="switch"
      aria-checked={isDark}
      aria-label={`Switch to ${next} theme`}
      title={`Switch to ${next} theme`}
      onClick={() => onChange(next)}
      className={`relative inline-flex h-7 w-12 shrink-0 cursor-pointer rounded-full border transition-colors focus:outline-none focus:ring-2 focus:ring-blue-400 focus:ring-offset-2 dark:focus:ring-offset-slate-950 ${
        isDark
          ? "bg-slate-700 border-slate-600"
          : "bg-slate-200 border-slate-300"
      }`}
    >
      <span
        aria-hidden="true"
        className={`pointer-events-none inline-flex h-5 w-5 transform items-center justify-center rounded-full bg-white shadow-md ring-0 transition mt-[2px] text-[11px] leading-none ${
          isDark ? "translate-x-[22px]" : "translate-x-[2px]"
        }`}
      >
        {isDark ? "🌙" : "☀"}
      </span>
    </button>
  );
}
