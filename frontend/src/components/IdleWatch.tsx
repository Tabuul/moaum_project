"use client";

/**
 * V437 — the idle session timeout, as the person sees it. The policy the Directorate of ICT set is read once (and kept
 * a few minutes); what the person does — a click, a key, a touch, a scroll, the pointer moving — is the activity, shared
 * with every tab of this browser; a request the browser makes on its own never is. At the warning the one dialog opens
 * with a countdown, and the person continues, saves what is unsaved, or signs out; at the end the session is ended through
 * the ordinary sign-out and the sign-in page says why. The server keeps its own clock and ends an idle session whatever
 * this shows: this is the courtesy, not the authority. An examination room is left to the CBT engine.
 */
import { useCallback, useEffect, useRef, useState } from "react";
import { usePathname } from "next/navigation";
import { Modal } from "@/components/proto/blocks";
import {
  BACKGROUND_HEADER, IDLE_EXPIRED_KEY, IDLE_LAST_KEY, IDLE_POLICY_KEY, canSaveUnsaved, clock, hasUnsaved, idleExempt, saveUnsaved,
  type SessionPolicy,
} from "@/lib/idle";

const POLICY_TTL_MS = 5 * 60_000;
const MOVE_THROTTLE_MS = 5_000;
/** the warning's own buttons: a press on one is that button's decision, so it must not first close the warning as ordinary activity
 *  (the dialog would be gone before the click landed, and Save changes or Log out now would never happen) */
const OWN_ACT = "data-idle-act";
const ownAct = (e: Event) => e.target instanceof Element && e.target.closest(`[${OWN_ACT}]`) !== null;

function readStored(key: string): number {
  try { return Number(localStorage.getItem(key)) || 0; } catch { return 0; }
}
function writeStored(key: string, v: number): void {
  try { localStorage.setItem(key, String(v)); } catch { /* a browser that keeps nothing: this tab's own clock still runs */ }
}

/** the policy in force, read through the BFF as the browser's own request (not activity), and kept a few minutes a tab */
async function readPolicy(): Promise<SessionPolicy | null> {
  try {
    const cached = sessionStorage.getItem(IDLE_POLICY_KEY);
    if (cached) {
      const c = JSON.parse(cached) as { t: number; p: SessionPolicy };
      if (Date.now() - c.t < POLICY_TTL_MS) return c.p;
    }
  } catch { /* read it afresh */ }
  try {
    const r = await fetch("/api/bff/api/v1/auth/session-policy", { headers: { [BACKGROUND_HEADER]: "1" }, cache: "no-store" });
    if (!r.ok) return null;
    const p = (await r.json()) as SessionPolicy;
    try { sessionStorage.setItem(IDLE_POLICY_KEY, JSON.stringify({ t: Date.now(), p })); } catch { /* fine */ }
    return p;
  } catch {
    return null;
  }
}

const HIDDEN: React.CSSProperties = { position: "absolute", width: 1, height: 1, overflow: "hidden", clip: "rect(0 0 0 0)", whiteSpace: "nowrap" };

export function IdleWatch() {
  const pathname = usePathname();
  const exempt = idleExempt(pathname);
  const [policy, setPolicy] = useState<SessionPolicy | null>(null);
  const [warning, setWarning] = useState(false);
  const [left, setLeft] = useState(0);
  const [busy, setBusy] = useState(false);
  const last = useRef(0);
  const lastMove = useRef(0);
  const warningRef = useRef(false);
  const ending = useRef(false);
  const continueBtn = useRef<HTMLButtonElement>(null);

  const mark = useCallback(() => {
    const now = Date.now();
    last.current = now;
    writeStored(IDLE_LAST_KEY, now);
  }, []);

  const closeWarning = useCallback(() => {
    if (!warningRef.current) return;
    warningRef.current = false;
    setWarning(false);
  }, []);

  /** the session ended through the ordinary sign-out; the sign-in page is told why when it was inactivity */
  const end = useCallback(async (why: "idle" | "out") => {
    if (ending.current) return;
    ending.current = true;
    if (why === "idle") writeStored(IDLE_EXPIRED_KEY, Date.now());
    await fetch("/api/auth/sign-out", { method: "POST" }).catch(() => null);
    const next = `${window.location.pathname}${window.location.search}`;
    window.location.assign(why === "idle" ? `/login?reason=idle&next=${encodeURIComponent(next)}` : "/login");
  }, []);

  useEffect(() => {
    if (exempt) return;
    let live = true;
    void readPolicy().then((p) => { if (live) setPolicy(p); });
    return () => { live = false; };
  }, [exempt]);

  // what the person does: a deliberate act always counts and closes the warning; the pointer moving counts only while no
  // warning shows (a nudge of the mouse is not a decision), and at most once in five seconds
  useEffect(() => {
    if (exempt) return;
    mark();
    const deliberate = (e: Event) => { if (ownAct(e)) return; mark(); closeWarning(); };
    const moved = () => {
      if (warningRef.current) return;
      const now = Date.now();
      if (now - lastMove.current < MOVE_THROTTLE_MS) return;
      lastMove.current = now;
      mark();
    };
    const onStorage = (e: StorageEvent) => {
      if (e.key === IDLE_EXPIRED_KEY && e.newValue) { void end("idle"); return; }
      if (e.key === IDLE_LAST_KEY && e.newValue) {
        const v = Number(e.newValue) || 0;
        if (v > last.current) { last.current = v; closeWarning(); }
      }
    };
    const opts: AddEventListenerOptions = { passive: true };
    window.addEventListener("pointerdown", deliberate, opts);
    window.addEventListener("keydown", deliberate);
    window.addEventListener("touchstart", deliberate, opts);
    window.addEventListener("wheel", deliberate, opts);
    window.addEventListener("scroll", deliberate, opts);
    window.addEventListener("pointermove", moved, opts);
    window.addEventListener("storage", onStorage);
    return () => {
      window.removeEventListener("pointerdown", deliberate);
      window.removeEventListener("keydown", deliberate);
      window.removeEventListener("touchstart", deliberate);
      window.removeEventListener("wheel", deliberate);
      window.removeEventListener("scroll", deliberate);
      window.removeEventListener("pointermove", moved);
      window.removeEventListener("storage", onStorage);
    };
  }, [exempt, mark, closeWarning, end]);

  // once a second: how long since the last activity in any tab, against the policy
  useEffect(() => {
    if (exempt || !policy || !policy.enabled) return;
    const id = window.setInterval(() => {
      const lastAll = Math.max(last.current, readStored(IDLE_LAST_KEY));
      const idle = (Date.now() - lastAll) / 1000;
      if (idle >= policy.idleSeconds) { void end("idle"); return; }
      const remaining = policy.idleSeconds - idle;
      if (remaining <= policy.warningSeconds) {
        setLeft(Math.ceil(remaining));
        if (!warningRef.current) { warningRef.current = true; setWarning(true); }
      } else {
        closeWarning();
      }
    }, 1000);
    return () => window.clearInterval(id);
  }, [exempt, policy, end, closeWarning]);

  useEffect(() => {
    if (warning) continueBtn.current?.focus();
  }, [warning]);

  /** the person's own act: the server's clock is touched too, and a session the server already ended is followed to the sign-in */
  async function keepGoing() {
    setBusy(true);
    try {
      mark();
      closeWarning();
      const r = await fetch("/api/bff/api/v1/iam/session", { cache: "no-store" });
      if (r.status === 401) void end("idle");
    } catch {
      /* offline for a moment: the next request will say */
    } finally {
      setBusy(false);
    }
  }

  async function saveThenGo() {
    setBusy(true);
    try {
      await saveUnsaved();
    } finally {
      setBusy(false);
    }
    await keepGoing();
  }

  if (exempt || !warning || !policy) return null;
  const unsaved = hasUnsaved();
  const spoken = left <= 5 ? left : Math.floor(left / 10) * 10;
  return (
    <Modal title="Session timeout warning" sub={unsaved ? "You have unsaved changes" : "You have been inactive"} onClose={() => void keepGoing()}
      foot={<>
        {policy.allowContinue !== false ? (
          <button ref={continueBtn} type="button" className="btn btn--primary btn--sm" data-idle-act="" disabled={busy} onClick={() => void keepGoing()}>Continue session</button>
        ) : null}
        {unsaved && canSaveUnsaved() ? <button type="button" className="btn btn--secondary btn--sm" data-idle-act="" disabled={busy} onClick={() => void saveThenGo()}>Save changes</button> : null}
        <button type="button" className="btn btn--ghost btn--sm" data-idle-act="" disabled={busy} onClick={() => void end("out")}>Log out now</button>
      </>}>
      <p style={{ marginTop: 0 }}>
        {unsaved ? "You have unsaved changes. Your session will expire and they will be lost unless you continue or save." : "You will be automatically logged out in:"}
      </p>
      <div className="tnum" aria-hidden="true" style={{ fontSize: 40, fontWeight: 800, letterSpacing: 1, lineHeight: 1.1, margin: "4px 0 8px" }}>{clock(left)}</div>
      <span aria-live="polite" style={HIDDEN}>You will be logged out in {spoken} second{spoken === 1 ? "" : "s"} due to inactivity.</span>
      <div className="sub2">Any click or key keeps the session; nothing happens on its own in the background.</div>
    </Modal>
  );
}
