"use client";

/**
 * A searchable dropdown (combobox): the look of the prototype's .ctl control,
 * but you can type to filter a long list — faculties, programmes, and the like.
 * Keyboard: ↑/↓ to move, Enter to choose, Esc to close; a click outside closes
 * it. Drop-in for a <select>: pass options and an optional "All …" label for the
 * empty value.
 */
import { useEffect, useId, useRef, useState } from "react";

export interface Opt { value: string; label: string }

export function SearchSelect({
  id,
  value,
  onChange,
  options,
  allLabel,
  placeholder,
  disabled,
}: {
  id?: string;
  value: string;
  onChange: (v: string) => void;
  options: Opt[];
  allLabel?: string;
  placeholder?: string;
  disabled?: boolean;
}) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [hi, setHi] = useState(0);
  const ref = useRef<HTMLDivElement>(null);
  const listId = useId();

  const all: Opt[] = allLabel != null ? [{ value: "", label: allLabel }, ...options] : options;
  const selectedLabel = all.find((o) => o.value === value)?.label ?? "";
  const q = query.trim().toLowerCase();
  const filtered = q ? all.filter((o) => o.label.toLowerCase().includes(q)) : all;

  useEffect(() => {
    function onDoc(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) { setOpen(false); setQuery(""); }
    }
    document.addEventListener("mousedown", onDoc);
    return () => document.removeEventListener("mousedown", onDoc);
  }, []);

  function choose(o: Opt) { onChange(o.value); setOpen(false); setQuery(""); }

  return (
    <div ref={ref} style={{ position: "relative" }}>
      <input
        id={id}
        className="ctl"
        role="combobox"
        aria-expanded={open}
        aria-controls={listId}
        aria-autocomplete="list"
        autoComplete="off"
        disabled={disabled}
        value={open ? query : selectedLabel}
        placeholder={open ? (selectedLabel || placeholder || "Type to search…") : (placeholder ?? "")}
        onFocus={() => { setOpen(true); setQuery(""); setHi(0); }}
        onChange={(e) => { setQuery(e.target.value); setOpen(true); setHi(0); }}
        onKeyDown={(e) => {
          if (e.key === "ArrowDown") { e.preventDefault(); setOpen(true); setHi((h) => Math.min(h + 1, Math.max(filtered.length - 1, 0))); }
          else if (e.key === "ArrowUp") { e.preventDefault(); setHi((h) => Math.max(h - 1, 0)); }
          else if (e.key === "Enter") { if (open && filtered[hi]) { e.preventDefault(); choose(filtered[hi]); } }
          else if (e.key === "Escape") { setOpen(false); setQuery(""); }
        }}
        style={{ paddingRight: 30 }}
      />
      <span aria-hidden="true" style={{ position: "absolute", right: 11, top: "50%", transform: "translateY(-50%)", pointerEvents: "none", color: "var(--muted)", fontSize: 11 }}>▼</span>
      {open ? (
        <div role="listbox" id={listId} style={{
          position: "absolute", zIndex: 30, top: "calc(100% + 4px)", left: 0, right: 0,
          maxHeight: 260, overflowY: "auto", background: "var(--surface)", border: "1px solid var(--line)",
          borderRadius: 8, boxShadow: "0 10px 28px rgba(16,40,52,.14)",
        }}>
          {filtered.length ? filtered.map((o, i) => (
            <div
              key={o.value || "__all"}
              role="option"
              aria-selected={o.value === value}
              onMouseDown={(e) => { e.preventDefault(); choose(o); }}
              onMouseEnter={() => setHi(i)}
              style={{
                padding: "8px 12px", cursor: "pointer", fontSize: 14,
                background: i === hi ? "var(--sky-bg)" : o.value === value ? "var(--bg)" : "transparent",
                color: o.value === value ? "var(--chrome-ink, var(--chrome))" : "var(--ink)",
                fontWeight: o.value === value ? 600 : 400,
              }}
            >
              {o.label}
            </div>
          )) : <div style={{ padding: "8px 12px", fontSize: 13, color: "var(--muted)" }}>No match</div>}
        </div>
      ) : null}
    </div>
  );
}
