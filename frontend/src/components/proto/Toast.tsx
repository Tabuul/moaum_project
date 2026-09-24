"use client";

/**
 * The portal's one notification: a toast that says what just happened — succeeded, failed, needs
 * attention, or is in hand — from any screen, without a blocking dialog. `notify("Saved")` is the
 * short form every desk already calls; `toast.success/error/warn/info(title, detail?)` is the long
 * form; `notifyProblem(problem)` turns an API refusal into the error toast the person should read,
 * never the status code. <ToastHost/> is mounted once in the Shell (and on the standalone pages).
 *
 * Behaviour: success clears in 4 s, information in 5 s, a warning in 6 s, an error in 7 s — an error
 * from the network or the server stays until dismissed. Hovering holds a toast; Escape or the close
 * button dismisses it; the same message twice within a moment shows once; at most five stand at a time.
 * The host is a polite live region; an error is an alert.
 */
import { useEffect, useRef, useState } from "react";
import type { Problem } from "@/lib/api";

export type Kind = "ok" | "bad" | "info" | "warn";
export interface Toast { id: number; kind: Kind; title: string; detail?: string; ttl: number; sticky?: boolean; out?: boolean }

const TTL: Record<Kind, number> = { ok: 4000, info: 5000, warn: 6000, bad: 7000 };
const MAX = 5;
const OUT_MS = 180;

let seq = 0;
const listeners = new Set<(t: Toast) => void>();
const recent = new Map<string, number>();

function emit(kind: Kind, title: string, detail?: string, opts: { ms?: number; sticky?: boolean } = {}) {
  const key = `${kind}|${title}|${detail ?? ""}`;
  const now = Date.now();
  const last = recent.get(key);
  if (last && now - last < 2500) return;   // the same word twice in a moment says nothing new
  recent.set(key, now);
  for (const [k, at] of recent) if (now - at > 10000) recent.delete(k);
  const t: Toast = { id: ++seq, kind, title, detail: detail?.trim() || undefined, ttl: opts.ms ?? TTL[kind], sticky: opts.sticky };
  listeners.forEach((l) => l(t));
}

/** Show a notification. Default kind "ok" (success); "bad" (error), "warn" (needs attention), "info". */
export function notify(message: string, kind: Kind = "ok", ms?: number) {
  emit(kind, message, undefined, { ms });
}

export const toast = {
  success: (title: string, detail?: string) => emit("ok", title, detail),
  error: (title: string, detail?: string, sticky = false) => emit("bad", title, detail, { sticky }),
  warn: (title: string, detail?: string) => emit("warn", title, detail),
  info: (title: string, detail?: string) => emit("info", title, detail),
};

/** what a person may read of an error: never a stack, a query or a class name */
function clean(s: string | undefined | null): string | undefined {
  if (!s) return undefined;
  const t = s.trim();
  if (!t) return undefined;
  if (/exception|stack|\bat [\w$.]+\(|\bselect\b.*\bfrom\b|nullpointer|traceback|\{"timestamp"/i.test(t)) return undefined;
  return t.length > 240 ? t.slice(0, 237) + "…" : t;
}

/** An API refusal as the error toast: the refusal's own title and remedy where it has them, or plain words for the status. */
export function notifyProblem(problem: Problem | null | undefined, fallbackTitle = "That did not go through") {
  const status = problem?.status ?? 0;
  const title = clean(problem?.title);
  const detail = clean(problem?.detail);
  const remedy = problem?.remedy?.message ? clean(problem.remedy.message) : undefined;
  const line = [detail, remedy].filter(Boolean).join(" ");
  if (status === 0 || status === 503 || status === 502 || status === 504) {
    emit("bad", "The portal could not reach the server", "Check your connection and try again; nothing was saved.", { sticky: true });
  } else if (status === 401) {
    emit("warn", "You are signed out", "Sign in again to continue.");
  } else if (status === 403) {
    emit("warn", title ?? "You do not have access to that", line || "This action belongs to another office.");
  } else if (status === 404) {
    emit("bad", title ?? "Not found", line || "There is nothing at that address any more.");
  } else if (status === 400 || (problem?.violations && problem.violations.length > 0)) {
    // a validation: something to complete or correct, in the refusal's own words — attention, not failure
    emit("warn", title ?? "Please check the form", line || undefined);
  } else if (status === 409 || status === 422) {
    // a business rule: the refusal's own words are the ones to read
    emit("bad", title ?? fallbackTitle, line || undefined);
  } else if (status >= 500) {
    emit("bad", "The portal could not complete that", "Something went wrong on the server; nothing was saved. Try again, and tell ICT if it persists.", { sticky: true });
  } else {
    emit("bad", title ?? fallbackTitle, line || undefined);
  }
}

const ICON: Record<Kind, string> = {
  ok: "M4 12.5 9.5 18 20 6.5",
  bad: "M6 6l12 12M18 6L6 18",
  warn: "M12 7v6M12 16.5v.5",
  info: "M12 8v.5M12 11v6",
};
const SR: Record<Kind, string> = { ok: "Success", bad: "Error", warn: "Attention", info: "Information" };

export function ToastHost() {
  const [toasts, setToasts] = useState<Toast[]>([]);
  const timers = useRef(new Map<number, number>());

  const remove = (id: number) => {
    const tm = timers.current.get(id);
    if (tm) { window.clearTimeout(tm); timers.current.delete(id); }
    setToasts((cur) => cur.map((x) => (x.id === id ? { ...x, out: true } : x)));
    window.setTimeout(() => setToasts((cur) => cur.filter((x) => x.id !== id)), OUT_MS);
  };
  const arm = (t: Toast) => {
    if (t.sticky) return;
    const tm = timers.current.get(t.id);
    if (tm) window.clearTimeout(tm);
    timers.current.set(t.id, window.setTimeout(() => remove(t.id), t.ttl));
  };
  const hold = (id: number) => { const tm = timers.current.get(id); if (tm) { window.clearTimeout(tm); timers.current.delete(id); } };

  useEffect(() => {
    const on = (t: Toast) => {
      setToasts((cur) => {
        const next = [...cur, t];
        const over = next.filter((x) => !x.out).length - MAX;
        if (over > 0) for (const x of next.filter((y) => !y.out).slice(0, over)) remove(x.id);
        return next;
      });
      arm(t);
    };
    listeners.add(on);
    const timersNow = timers.current;
    return () => { listeners.delete(on); timersNow.forEach((tm) => window.clearTimeout(tm)); timersNow.clear(); };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <div className="toast-host" aria-live="polite" aria-relevant="additions">
      {toasts.map((t) => (
        <div
          key={t.id}
          role={t.kind === "bad" ? "alert" : "status"}
          tabIndex={0}
          className={`toast toast--${t.kind}${t.out ? " is-out" : ""}`}
          onMouseEnter={() => hold(t.id)}
          onMouseLeave={() => arm(t)}
          onFocus={() => hold(t.id)}
          onBlur={() => arm(t)}
          onKeyDown={(e) => { if (e.key === "Escape") remove(t.id); }}
        >
          <span aria-hidden="true" className="toast__i">
            <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.6" strokeLinecap="round" strokeLinejoin="round"><path d={ICON[t.kind]} /></svg>
          </span>
          <div className="toast__b">
            <span className="sr-only">{SR[t.kind]}: </span>
            <div className="toast__t">{t.title}</div>
            {t.detail ? <div className="toast__d">{t.detail}</div> : null}
          </div>
          <button type="button" className="toast__x" aria-label="Dismiss" onClick={() => remove(t.id)}>
            <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round"><path d="M6 6l12 12M18 6L6 18" /></svg>
          </button>
        </div>
      ))}
    </div>
  );
}
