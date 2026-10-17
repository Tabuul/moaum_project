"use client";

/**
 * V521: while ICT Support views a student's portal as the student, every screen says so at its top — whose portal it is, that
 * nothing is changed from it, how long is left — with the one way out: LEAVE STUDENT VIEW, which ends the view and brings the
 * agent's own session back. Nothing shows for the student themselves.
 */
import { useEffect, useMemo, useState, useSyncExternalStore } from "react";
import { SUPPORT_VIEW_COOKIE, readSupportView, timeLeft, type SupportViewState } from "@/lib/support-view";

/** the cookie's raw value: a string, so the snapshot stays the same between renders while the cookie does */
function cookieRaw(): string | null {
  return document.cookie.split("; ").find((c) => c.startsWith(`${SUPPORT_VIEW_COOKIE}=`))?.slice(SUPPORT_VIEW_COOKIE.length + 1) ?? null;
}
const noChanges = () => () => {};

/** the student view the browser is in, or null — the cookie is the browser's, so the server renders none */
export function useSupportView(): SupportViewState | null {
  const raw = useSyncExternalStore(noChanges, cookieRaw, () => null);
  return useMemo(() => readSupportView(raw), [raw]);
}

export function SupportViewBanner() {
  const view = useSupportView();
  const [now, setNow] = useState(() => Date.now());
  const [leaving, setLeaving] = useState(false);

  useEffect(() => {
    const t = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(t);
  }, []);

  if (!view) return null;

  async function leave() {
    setLeaving(true);
    const r = await fetch("/api/auth/support-view/exit", { method: "POST" }).catch(() => null);
    const j = r && r.ok ? ((await r.json().catch(() => null)) as { redirect?: string } | null) : null;
    window.location.replace(j?.redirect ?? "/helpdesk");
  }

  return (
    <div role="status" aria-live="polite" style={{ position: "sticky", top: 0, zIndex: 60, background: "var(--red-deep, #7f1d1d)", color: "#fff",
      padding: "8px 16px", display: "flex", flexWrap: "wrap", alignItems: "center", gap: 12, fontSize: "var(--t-sm, 13px)" }}>
      <span style={{ fontWeight: 700, letterSpacing: ".3px" }}>ICT SUPPORT — STUDENT VIEW</span>
      <span className="grow" style={{ flex: "1 1 260px" }}>
        You are viewing the portal of <b>{view.name}</b>{view.matricNo ? <> ({view.matricNo})</> : null} as the student sees it. It is read-only: nothing
        is changed from here. {timeLeft(view.endsAt, now)} left.
      </span>
      <button type="button" className="btn btn--sm" style={{ background: "#fff", color: "var(--red-deep, #7f1d1d)", fontWeight: 700 }}
        disabled={leaving} aria-busy={leaving} onClick={() => void leave()}>{leaving ? "Leaving..." : "LEAVE STUDENT VIEW"}</button>
    </div>
  );
}
