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
    <div ref={ref} className="ss">
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
      />
      <span aria-hidden="true" className="ss__caret">▼</span>
      {open ? (
        <div role="listbox" id={listId} className="ss__list">
          {filtered.length ? filtered.map((o, i) => (
            <div
              key={o.value || "__all"}
              role="option"
              aria-selected={o.value === value}
              onMouseDown={(e) => { e.preventDefault(); choose(o); }}
              onMouseEnter={() => setHi(i)}
              className={`ss__opt${i === hi ? " is-hi" : ""}`}
            >
              {o.label}
            </div>
          )) : <div className="ss__none">No match</div>}
        </div>
      ) : null}
    </div>
  );
}
