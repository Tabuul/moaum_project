"use client";

/**
 * The rest of the prototype's shared building blocks, ported as they are:
 * step(), idSteps(), gate() (part3/part25), row() (part3), bar() (part7),
 * two_col() (part13), passport() (part4c) and modal() (part34). Same
 * classes, same inline styles, same structure — the stylesheet is the
 * prototype's, so the markup has to be too.
 */
import type { ReactNode } from "react";
import { Tick } from "./ui";

/** step(state, title, sub) — one step of a ladder */
export function Step({ state, title, sub }: { state: "done" | "now" | "todo"; title: ReactNode; sub: ReactNode }) {
  const mark =
    state === "done" ? (
      <div className="step__mark step__mark--done">
        <Tick size={12} colour="#fff" />
      </div>
    ) : state === "now" ? (
      <div className="step__mark step__mark--now">
        <div style={{ width: 7, height: 7, borderRadius: 4, background: "var(--red)" }} />
      </div>
    ) : (
      <div className="step__mark step__mark--todo" />
    );
  return (
    <div className="step">
      {mark}
      <div>
        <div style={{ fontSize: 13.5, fontWeight: state === "now" ? 700 : 500 }}>{title}</div>
        <div className="sub2">{sub}</div>
      </div>
    </div>
  );
}

/** idSteps(list) */
export function Steps({ list }: { list: ["done" | "now" | "todo", ReactNode, ReactNode][] }) {
  return (
    <div className="steps">
      {list.map((s, i) => (
        <Step key={i} state={s[0]} title={s[1]} sub={s[2]} />
      ))}
    </div>
  );
}

/** gate(state, title, sub, last) — one row of a bordered checklist */
export function Gate({ state, title, sub, last }: { state: "done" | "todo"; title: ReactNode; sub: ReactNode; last?: boolean }) {
  return (
    <div style={{ padding: "14px 16px", display: "flex", gap: 12, borderBottom: last ? undefined : "1px solid var(--line-2)" }}>
      {state === "done" ? (
        <div className="step__mark step__mark--done">
          <Tick size={12} colour="#fff" />
        </div>
      ) : (
        <div className="step__mark step__mark--todo" />
      )}
      <div>
        <div style={{ fontWeight: 600, color: state === "todo" ? "var(--faint)" : undefined }}>{title}</div>
        <div className="sub2">{sub}</div>
      </div>
    </div>
  );
}

/** the bordered box the gates sit in */
export function Gates({ children }: { children: ReactNode }) {
  return <div style={{ border: "1px solid var(--line)", borderRadius: 8, overflow: "hidden" }}>{children}</div>;
}

/** row(k, v, colour) — a label and a figure, apart */
export function Row({ k, v, colour }: { k: ReactNode; v: ReactNode; colour?: string }) {
  return (
    <div style={{ display: "flex", justifyContent: "space-between" }}>
      <span className="sub2">{k}</span>
      <span className="tnum" style={{ fontWeight: 600, fontSize: 12.5, color: colour }}>
        {v}
      </span>
    </div>
  );
}

/** bar(pct, colour) — a meter */
export function Bar({ pct, colour = "var(--chrome)" }: { pct: number; colour?: string }) {
  return (
    <div className="meter__bar" style={{ minWidth: 90 }}>
      <div className="meter__fill" style={{ width: `${Math.max(0, Math.min(100, pct))}%`, background: colour }} />
    </div>
  );
}

/** two_col(a, b) */
export function TwoCol({ children }: { children: ReactNode }) {
  return (
    <div className="grid grid--2" style={{ alignItems: "start" }}>
      {children}
    </div>
  );
}

/** passport(w, h, radius) — the neutral placeholder portrait, or the photograph itself */
export function Passport({ w, h, radius = 4, src, alt }: { w: number; h: number; radius?: number; src?: string | null; alt?: string }) {
  return (
    <div style={{ width: w, height: h, borderRadius: radius, overflow: "hidden", border: "1px solid var(--line)", flexShrink: 0, background: "#DCE6EC" }}>
      {src ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={src} alt={alt ?? "Passport photograph"} loading="lazy" style={{ width: "100%", height: "100%", objectFit: "cover", display: "block" }} />
      ) : (
        <svg viewBox="0 0 100 124" width="100%" height="100%" role="img" aria-label="Student passport photograph">
          <rect width="100" height="124" fill="#DCE6EC" />
          <circle cx="50" cy="46" r="22" fill="#94A9B6" />
          <path d="M14 124c0-22 16-35 36-35s36 13 36 35Z" fill="#94A9B6" />
        </svg>
      )}
    </div>
  );
}

/** modal(title, sub, body, foot, wide) */
export function Modal({
  title,
  sub,
  children,
  foot,
  wide,
  onClose,
}: {
  title: ReactNode;
  sub?: ReactNode;
  children: ReactNode;
  foot?: ReactNode;
  wide?: boolean;
  onClose: () => void;
}) {
  return (
    <div className="mdl" role="dialog" aria-modal="true" onClick={onClose} onKeyDown={(e) => { if (e.key === "Escape") { e.stopPropagation(); onClose(); } }}>
      <div className={`mdl__box${wide ? " is-wide" : ""}`} onClick={(e) => e.stopPropagation()} tabIndex={-1} autoFocus>
        <div className="mdl__head">
          <div style={{ minWidth: 0 }}>
            <b>{title}</b>
            {sub ? <span className="mdl__sub">{sub}</span> : null}
          </div>
          <button className="mdl__x" aria-label="Close" onClick={onClose}>
            &times;
          </button>
        </div>
        <div className="mdl__body">{children}</div>
        {foot ? <div className="mdl__foot">{foot}</div> : null}
      </div>
    </div>
  );
}

/** the prototype's field: label, control, hint */
export function Field({
  id,
  label,
  hint,
  full,
  required,
  error,
  children,
}: {
  id: string;
  label: ReactNode;
  hint?: ReactNode;
  full?: boolean;
  /** marks the label; the control's own required attribute still does the checking */
  required?: boolean;
  /** an error line under the control, and the control drawn in the error state */
  error?: ReactNode;
  children: ReactNode;
}) {
  return (
    <div className={`field${full ? " rf--full" : ""}${error ? " is-error" : ""}`}>
      <label htmlFor={id}>{label}{required ? <span className="req" aria-hidden="true"> *</span> : null}</label>
      {children}
      {error ? <span className="ferr" role="alert">{error}</span> : null}
      {hint && !error ? <span className="hint">{hint}</span> : null}
    </div>
  );
}

/** "MOAUM/CSC/23/1487" in the tabular figures the prototype uses for every identifier */
export function Num({ children, sub }: { children: ReactNode; sub?: boolean }) {
  return <span className={`tnum${sub ? " sub2" : ""}`}>{children}</span>;
}

/** money() and day() are pure formatters; they live in @/lib/format so a server
 *  component can call them, and are re-exported here for existing client imports. */
export { money, day } from "@/lib/format";
