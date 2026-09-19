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
const TONE: Record<Kind, { ring: string; ink: string }> = {
  ok: { ring: "var(--green, #1a7f4b)", ink: "var(--green-ink, #1a7f4b)" },
  bad: { ring: "var(--red, #b3261e)", ink: "var(--red-ink, #b3261e)" },
  info: { ring: "var(--chrome, #0e3f55)", ink: "var(--chrome, #0e3f55)" },
};

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
    <div aria-live="polite" style={{
      position: "fixed", top: "calc(env(safe-area-inset-top, 0px) + 18px)", left: "50%", transform: "translateX(-50%)",
      zIndex: 10000, display: "flex", flexDirection: "column", gap: 10, alignItems: "center", pointerEvents: "none", width: "min(92vw, 460px)",
    }}>
      {toasts.map((t) => (
        <div key={t.id} role="status" onClick={() => setToasts((cur) => cur.filter((x) => x.id !== t.id))} style={{
          pointerEvents: "auto", cursor: "pointer", display: "flex", alignItems: "center", gap: 12,
          background: "#fff", color: "#16273a", border: "1px solid var(--line, #e4ddcd)", borderLeft: `4px solid ${TONE[t.kind].ring}`,
          borderRadius: 12, padding: "13px 16px", boxShadow: "0 8px 30px rgba(20,39,58,.18)", width: "100%",
          animation: "toastIn .18s ease-out",
        }}>
          <span aria-hidden style={{
            flex: "0 0 auto", width: 26, height: 26, borderRadius: "50%", background: TONE[t.kind].ring, color: "#fff",
            display: "inline-flex", alignItems: "center", justifyContent: "center", fontSize: 15, fontWeight: 700,
          }}>{ICON[t.kind]}</span>
          <span style={{ fontSize: 14, fontWeight: 600, lineHeight: 1.35 }}>{t.message}</span>
        </div>
      ))}
      <style>{"@keyframes toastIn{from{opacity:0;transform:translateY(-8px)}to{opacity:1;transform:none}}"}</style>
    </div>
  );
}
