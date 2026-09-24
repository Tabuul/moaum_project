"use client";

/**
 * App-wide popup notifications — a SweetAlert-style confirmation that appears and
 * fades itself out, so a save on any screen can say so without a blocking dialog.
 * Call notify("Saved") from anywhere; <ToastHost/> is mounted once in the Shell.
 */
import { useEffect, useState } from "react";

type Kind = "ok" | "bad" | "info";
export interface Toast { id: number; message: string; kind: Kind; ttl: number }

let seq = 0;
const listeners = new Set<(t: Toast) => void>();

/** Show a popup notification. Default kind "ok" (green check); "bad" (red) for a failure, "info" (blue). */
export function notify(message: string, kind: Kind = "ok", ms = 3200) {
  const t: Toast = { id: ++seq, message, kind, ttl: ms };
  listeners.forEach((l) => l(t));
}

const ICON: Record<Kind, string> = { ok: "✓", bad: "✕", info: "i" };

export function ToastHost() {
  const [toasts, setToasts] = useState<Toast[]>([]);
  useEffect(() => {
    const on = (t: Toast) => {
      setToasts((cur) => [...cur, t]);
      window.setTimeout(() => setToasts((cur) => cur.filter((x) => x.id !== t.id)), t.ttl);
    };
    listeners.add(on);
    return () => { listeners.delete(on); };
  }, []);

  return (
    <div aria-live="polite" className="toast-host">
      {toasts.map((t) => (
        <div key={t.id} role="status" className={`toast toast--${t.kind}`} onClick={() => setToasts((cur) => cur.filter((x) => x.id !== t.id))}>
          <span aria-hidden className="toast__i">{ICON[t.kind]}</span>
          <span className="toast__m">{t.message}</span>
        </div>
      ))}
    </div>
  );
}
