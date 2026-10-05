"use client";
/** The examination room (V322): one attempt, fullscreen, the server's clock, the answers saved as the candidate goes, the browser's reports —
 *  the tab hidden, the window losing focus, fullscreen exited, the connection lost, copy and paste — sent to the server, which warns or ends
 *  the attempt by the examination's policy. The paper arrives without its keys; the screen never has them. A standard browser cannot stop a
 *  candidate switching to another application or device, and this screen does not pretend to: it reports what it can see. */
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { clock, type Room, type RoomQuestion } from "@/lib/cbt";
import { tokenKey } from "./MyExams";

type Phase = "loading" | "gate" | "writing" | "ended" | "replaced" | "noToken" | "error";
interface Warn { level: "WARNING" | "FINAL_WARNING"; violations: number; limit: number }

const HEARTBEAT_MS = 30_000;
const SAVE_DEBOUNCE_MS = 1200;

export function ExamRoom({ attemptId }: { attemptId: string }) {
  const router = useRouter();
  const [phase, setPhase] = useState<Phase>("loading");
  const [room, setRoom] = useState<Room | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [answers, setAnswers] = useState<Record<string, number[]>>({});
  const [current, setCurrent] = useState(0);
  const [offset, setOffset] = useState(0);
  const [endsAt, setEndsAt] = useState<number>(0);
  /* the clock read once per tick, so a render is pure */
  const [now, setNow] = useState(() => Date.now());
  const [unsaved, setUnsaved] = useState(0);
  const [offline, setOffline] = useState(false);
  const [warn, setWarn] = useState<Warn | null>(null);
  const [fullscreenLost, setFullscreenLost] = useState(false);
  const [endStatus, setEndStatus] = useState<string>("");
  const [confirming, setConfirming] = useState(false);
  const [busy, setBusy] = useState(false);
  const token = useRef<string | null>(null);
  const pending = useRef<Map<string, number[]>>(new Map());
  const saveTimer = useRef<number | null>(null);
  const eventQueue = useRef<{ kind: string; detail?: string }[]>([]);
  const hiddenAt = useRef<number | null>(null);
  const lastBlurReport = useRef(0);
  const lastCopyReport = useRef(0);
  const phaseRef = useRef<Phase>("loading");
  const endsAtRef = useRef(0);
  const offsetRef = useRef(0);
  const submitRef = useRef<(auto: boolean) => Promise<void>>(async () => undefined);
  useEffect(() => { phaseRef.current = phase; }, [phase]);
  useEffect(() => { endsAtRef.current = endsAt; }, [endsAt]);
  useEffect(() => { offsetRef.current = offset; }, [offset]);

  const headers = useCallback((): HeadersInit => ({ "Content-Type": "application/json", "X-Attempt-Token": token.current ?? "" }), []);

  const end = useCallback((status: string) => {
    setEndStatus(status);
    setPhase("ended");
    if (document.fullscreenElement) document.exitFullscreen().catch(() => undefined);
  }, []);

  const handleProblem = useCallback((p: Problem): boolean => {
    const code = (p as { code?: string }).code;
    if (code === "CBT_SESSION_REPLACED") { setPhase("replaced"); return true; }
    if (code === "CBT_ATTEMPT_CLOSED") { end("CLOSED"); return true; }
    return false;
  }, [end]);

  /* ── the paper ── */
  const load = useCallback(async () => {
    try { token.current = sessionStorage.getItem(tokenKey(attemptId)); } catch { token.current = null; }
    if (!token.current) { setPhase("noToken"); return; }
    const r = await fetch(`/api/bff/api/v1/me/cbt/attempts/${attemptId}`, { headers: headers() });
    const j = await r.json().catch(() => null);
    if (!r.ok) { const p = (j as Problem) ?? { status: r.status, title: r.statusText }; if (!handleProblem(p)) { setProblem(p); setPhase("error"); } return; }
    const rm = j as Room;
    setRoom(rm);
    setAnswers(rm.answers ?? {});
    setOffset(new Date(rm.now).getTime() - Date.now());
    setEndsAt(new Date(rm.attempt.ends_at).getTime());
    if (rm.attempt.status !== "IN_PROGRESS") { end(rm.attempt.status); return; }
    setPhase("gate");
  }, [attemptId, headers, handleProblem, end]);
  useEffect(() => { const t = window.setTimeout(() => void load(), 0); return () => window.clearTimeout(t); }, [load]);

  /* ── the server's clock, ticking locally; at the end of time the attempt submits itself ── */
  useEffect(() => {
    const id = window.setInterval(() => {
      const n = Date.now();
      setNow(n);
      if (phaseRef.current === "writing" && endsAtRef.current && n + offsetRef.current >= endsAtRef.current) void submitRef.current(true);
    }, 1000);
    return () => window.clearInterval(id);
  }, []);
  const serverNow = now + offset;
  const left = Math.max(0, (endsAt - serverNow) / 1000);

  /* ── answers: debounced, batched, retried ── */
  const flushAnswers = useCallback(async (): Promise<boolean> => {
    if (!pending.current.size || phaseRef.current !== "writing") return true;
    const batch = [...pending.current.entries()].map(([q, a]) => ({ q, a }));
    try {
      const r = await fetch(`/api/bff/api/v1/me/cbt/attempts/${attemptId}/answers`, { method: "PUT", headers: headers(), body: JSON.stringify({ answers: batch }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const p = (j as Problem) ?? { status: r.status, title: r.statusText }; if (handleProblem(p)) return false; setUnsaved(pending.current.size); return false; }
      for (const b of batch) { const now = pending.current.get(b.q); if (now && now === b.a) pending.current.delete(b.q); }
      setUnsaved(pending.current.size);
      if (j && j.status && j.status !== "IN_PROGRESS") end(j.status);
      return true;
    } catch {
      setUnsaved(pending.current.size);
      return false;
    }
  }, [attemptId, headers, handleProblem, end]);

  const choose = (q: RoomQuestion, i: number) => {
    setAnswers((prev) => {
      const was = prev[q.id] ?? [];
      const next = q.kind === "MULTI" ? (was.includes(i) ? was.filter((x) => x !== i) : [...was, i].sort((a, b) => a - b)) : [i];
      pending.current.set(q.id, next);
      setUnsaved(pending.current.size);
      return { ...prev, [q.id]: next };
    });
    if (saveTimer.current) window.clearTimeout(saveTimer.current);
    saveTimer.current = window.setTimeout(() => void flushAnswers(), SAVE_DEBOUNCE_MS);
  };
  const clear = (q: RoomQuestion) => {
    setAnswers((prev) => { const n = { ...prev }; delete n[q.id]; pending.current.set(q.id, []); setUnsaved(pending.current.size); return n; });
    if (saveTimer.current) window.clearTimeout(saveTimer.current);
    saveTimer.current = window.setTimeout(() => void flushAnswers(), SAVE_DEBOUNCE_MS);
  };

  /* ── the browser's reports ── */
  const flushEvents = useCallback(async () => {
    if (!eventQueue.current.length || phaseRef.current !== "writing") return;
    const batch = eventQueue.current.splice(0, eventQueue.current.length);
    try {
      const r = await fetch(`/api/bff/api/v1/me/cbt/attempts/${attemptId}/events`, { method: "POST", headers: headers(), body: JSON.stringify({ events: batch }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const p = (j as Problem) ?? { status: r.status, title: r.statusText }; if (!handleProblem(p)) eventQueue.current.unshift(...batch); return; }
      if (j.action === "SUBMITTED" || j.action === "TERMINATED") { end(j.action); return; }
      if (j.level) setWarn({ level: j.level, violations: Number(j.violations), limit: Number(j.limit) });
    } catch { eventQueue.current.unshift(...batch); }
  }, [attemptId, headers, handleProblem, end]);
  const report = useCallback((kind: string, detail?: string) => { eventQueue.current.push({ kind, detail }); void flushEvents(); }, [flushEvents]);

  useEffect(() => {
    if (phase !== "writing") return;
    const onVisibility = () => {
      if (document.visibilityState === "hidden") { hiddenAt.current = Date.now(); report("TAB_SWITCH", "the examination tab was hidden"); }
      else if (hiddenAt.current) { const s = Math.round((Date.now() - hiddenAt.current) / 1000); hiddenAt.current = null; report("RESUMED", `back after ${s}s`); }
    };
    const onBlur = () => { if (document.visibilityState === "hidden" || Date.now() - lastBlurReport.current < 1500) return; lastBlurReport.current = Date.now(); report("WINDOW_BLUR", "the examination window lost focus"); };
    const onFullscreen = () => { if (!document.fullscreenElement) { setFullscreenLost(true); report("FULLSCREEN_EXIT", "fullscreen was exited"); } else setFullscreenLost(false); };
    const onOffline = () => { setOffline(true); eventQueue.current.push({ kind: "NETWORK_DISCONNECT", detail: "the browser went offline" }); };
    const onOnline = () => { setOffline(false); report("RECONNECTED", "the browser is back online"); void flushAnswers(); };
    const onCopy = (e: Event) => { e.preventDefault(); if (Date.now() - lastCopyReport.current > 30_000) { lastCopyReport.current = Date.now(); report("COPY_PASTE", e.type); } };
    const onContext = (e: Event) => { e.preventDefault(); if (Date.now() - lastCopyReport.current > 30_000) { lastCopyReport.current = Date.now(); report("CONTEXT_MENU"); } };
    document.addEventListener("visibilitychange", onVisibility);
    window.addEventListener("blur", onBlur);
    document.addEventListener("fullscreenchange", onFullscreen);
    window.addEventListener("offline", onOffline);
    window.addEventListener("online", onOnline);
    document.addEventListener("copy", onCopy); document.addEventListener("cut", onCopy); document.addEventListener("paste", onCopy);
    document.addEventListener("contextmenu", onContext);
    return () => {
      document.removeEventListener("visibilitychange", onVisibility); window.removeEventListener("blur", onBlur); document.removeEventListener("fullscreenchange", onFullscreen);
      window.removeEventListener("offline", onOffline); window.removeEventListener("online", onOnline);
      document.removeEventListener("copy", onCopy); document.removeEventListener("cut", onCopy); document.removeEventListener("paste", onCopy); document.removeEventListener("contextmenu", onContext);
    };
  }, [phase, report, flushAnswers]);

  /* ── the heartbeat: the server's word on the attempt every half minute, and a retry of anything unsaved ── */
  const heartbeat = useCallback(async () => {
    if (phaseRef.current !== "writing") return;
    await flushAnswers();
    await flushEvents();
    try {
      const r = await fetch(`/api/bff/api/v1/me/cbt/attempts/${attemptId}/ping`, { method: "POST", headers: headers(), body: "{}" });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const p = (j as Problem) ?? { status: r.status, title: r.statusText }; handleProblem(p); return; }
      setOffset(new Date(j.now).getTime() - Date.now());
      if (j.endsAt) setEndsAt(new Date(j.endsAt).getTime());
      if (j.status !== "IN_PROGRESS") end(j.status);
      setOffline(false);
    } catch { setOffline(true); }
  }, [attemptId, headers, handleProblem, end, flushAnswers, flushEvents]);
  useEffect(() => { if (phase !== "writing") return; const id = window.setInterval(() => void heartbeat(), HEARTBEAT_MS); return () => window.clearInterval(id); }, [phase, heartbeat]);

  /* ── the end of time: submit what was saved ── */
  const submit = useCallback(async (auto: boolean) => {
    if (phaseRef.current !== "writing") return;
    setBusy(true);
    try {
      await flushAnswers();
      const r = await fetch(`/api/bff/api/v1/me/cbt/attempts/${attemptId}/submit`, { method: "POST", headers: headers(), body: "{}" });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const p = (j as Problem) ?? { status: r.status, title: r.statusText }; if (!handleProblem(p)) { if (auto) end("TIME_EXPIRED"); else setProblem(p); } return; }
      end(j.status ?? "SUBMITTED");
    } catch { if (auto) end("TIME_EXPIRED"); else setProblem({ status: 0, title: "The submission could not reach the server. Stay on this screen; it will retry." }); }
    finally { setBusy(false); setConfirming(false); }
  }, [attemptId, headers, handleProblem, end, flushAnswers]);
  useEffect(() => { submitRef.current = submit; }, [submit]);

  /* fullscreen asked for, but never waited on for long: a browser that refuses or never answers still lets the candidate write */
  const goFullscreen = () => Promise.race([
    document.documentElement.requestFullscreen?.() ?? Promise.resolve(),
    new Promise<void>((resolve) => window.setTimeout(resolve, 1500)),
  ]).catch(() => undefined);
  const begin = async () => {
    await goFullscreen();
    setPhase("writing");
    report("RESUMED", "the examination screen was entered");
  };
  const returnToFullscreen = async () => { await goFullscreen(); if (document.fullscreenElement) setFullscreenLost(false); };

  const questions = useMemo(() => room?.questions ?? [], [room]);
  const q = questions[current];
  const answered = useMemo(() => questions.filter((x) => (answers[x.id] ?? []).length > 0).length, [questions, answers]);
  const low = left < 300;

  if (phase === "loading") return <Screen><p className="sub2">Opening your examination…</p></Screen>;
  if (phase === "noToken") return <Screen title="This screen does not hold your attempt"><p>Open the examination again from your CBT examinations page; your attempt continues where it was.</p><a className="btn btn--primary" href="/student/cbt">GST CBT Examinations</a></Screen>;
  if (phase === "replaced") return <Screen title="Your examination was opened elsewhere"><p>The attempt continues on the browser or device where it was opened last. This screen no longer holds it, and the second sign-in is on the record.</p><a className="btn btn--ghost" href="/student/cbt">Back to CBT examinations</a></Screen>;
  if (phase === "error") return <Screen title="The examination could not be opened"><p>{problem?.detail ?? problem?.title}</p><a className="btn btn--ghost" href="/student/cbt">Back to CBT examinations</a></Screen>;
  if (phase === "ended") {
    const words: Record<string, [string, string]> = {
      SUBMITTED: ["Examination submitted", "Your answers are submitted and scored. Your result is published by the office; you will be told when it is out."],
      TIME_EXPIRED: ["Time expired", "The examination ended at the end of your time. Whatever you had answered is submitted and scored. Your result is published by the office."],
      TERMINATED: ["Examination terminated", "Your examination was ended under the University's examination policy. The record is reviewed by the office."],
      CLOSED: ["Examination closed", "The examination was closed. Whatever you had answered is submitted and scored."],
    };
    const [t, text] = words[endStatus] ?? ["Examination ended", "Your attempt is no longer open."];
    return <Screen title={t}><p>{text}</p><a className="btn btn--primary" href="/student/cbt" onClick={() => { try { sessionStorage.removeItem(tokenKey(attemptId)); } catch { /* ignored */ } }}>Back to CBT examinations</a></Screen>;
  }
  if (!room) return <Screen><p className="sub2">…</p></Screen>;
  if (phase === "gate") {
    return (
      <Screen title={`${room.exam.course_code} · ${room.exam.title}`}>
        <p>{room.attempt.questions} questions · {room.attempt.max_marks} marks · your time ends at <b className="tnum">{new Date(room.attempt.ends_at).toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" })}</b> ({clock(left)} left).</p>
        <p className="sub2">The examination opens in fullscreen. Leaving the tab, losing the window&rsquo;s focus or exiting fullscreen is recorded; {room.exam.violation_limit} such event{room.exam.violation_limit === 1 ? " is" : "s are"} allowed. Your answers are saved as you go.</p>
        {room.attempt.number > 1 || room.attempt.answered ? <p className="sub2">You return to the attempt as you left it: {room.attempt.answered} answered.</p> : null}
        <button type="button" className="btn btn--primary" onClick={() => void begin()}>ENTER THE EXAMINATION</button>
      </Screen>
    );
  }

  return (
    <div style={{ minHeight: "100vh", background: "var(--paper, #f6f7f9)", display: "flex", flexDirection: "column", userSelect: "none" }}>
      <header style={{ position: "sticky", top: 0, zIndex: 5, display: "flex", alignItems: "center", gap: 16, padding: "10px 16px", background: "var(--ink, #10233b)", color: "#fff" }}>
        <div style={{ minWidth: 0, flex: 1 }}>
          <div style={{ fontWeight: 700 }}>{room.exam.course_code} · {room.exam.title}</div>
          <div style={{ fontSize: 12, opacity: 0.85 }}>{room.exam.session} · semester {room.exam.semester} · attempt {room.attempt.number}</div>
        </div>
        <div className="tnum" style={{ fontSize: 12, opacity: 0.9 }}>{answered} of {questions.length} answered{unsaved ? ` · ${unsaved} saving…` : " · saved"}</div>
        <div className="tnum" aria-live="polite" style={{ fontSize: 24, fontWeight: 700, padding: "4px 12px", borderRadius: 6, background: low ? "#b3261e" : "rgba(255,255,255,0.12)" }}>{clock(left)}</div>
        <button type="button" className="btn btn--go" disabled={busy} onClick={() => setConfirming(true)}>SUBMIT</button>
      </header>
      {offline ? <div role="status" style={{ background: "#fde7c4", padding: "8px 16px", fontSize: 14 }}>Your connection has been interrupted. Please remain on the examination screen while the system attempts to reconnect. Your answers are kept here and saved when the connection returns; the clock continues.</div> : null}
      {fullscreenLost ? <div role="status" style={{ background: "#fbdcd9", padding: "8px 16px", fontSize: 14, display: "flex", gap: 12, alignItems: "center" }}><span>You have exited fullscreen mode. This has been recorded.</span><button type="button" className="btn btn--primary btn--sm" onClick={() => void returnToFullscreen()}>Return to fullscreen</button></div> : null}
      <main style={{ display: "grid", gridTemplateColumns: "minmax(0, 1fr) 260px", gap: 16, padding: 16, flex: 1 }}>
        <section className="card" style={{ padding: 20 }}>
          {q ? (
            <>
              <div className="sub2 tnum">Question {q.n} of {questions.length} · {q.marks} mark{q.marks === 1 ? "" : "s"} · {q.kind === "MULTI" ? (room.exam.partial_credit ? "select every correct option · each right one earns a share, each wrong one costs a share" : "select every correct option · marks only for exactly the right set") : q.kind === "TRUE_FALSE" ? "true or false" : "select one option"}</div>
              <div style={{ fontSize: 18, margin: "12px 0 16px", whiteSpace: "pre-wrap" }}>{q.stem}</div>
              <div style={{ display: "grid", gap: 8 }}>
                {q.options.map((o, idx) => {
                  const on = (answers[q.id] ?? []).includes(o.i);
                  return (
                    <label key={o.i} style={{ display: "flex", gap: 12, alignItems: "flex-start", padding: "12px 14px", border: `1px solid ${on ? "var(--ink, #10233b)" : "var(--line, #d9dee5)"}`, borderRadius: 8, background: on ? "rgba(16,35,59,0.06)" : "#fff", cursor: "pointer" }}>
                      <input type={q.kind === "MULTI" ? "checkbox" : "radio"} name={`q-${q.id}`} checked={on} onChange={() => choose(q, o.i)} style={{ marginTop: 3 }} />
                      <span><b className="tnum">{String.fromCharCode(65 + idx)}.</b> {o.text}</span>
                    </label>
                  );
                })}
              </div>
              <div className="row row--inline row--tight mt-3" style={{ justifyContent: "space-between" }}>
                <button type="button" className="btn btn--ghost" disabled={current === 0} onClick={() => setCurrent(current - 1)}>Previous</button>
                <span className="row row--inline row--tight">
                  {(answers[q.id] ?? []).length ? <button type="button" className="btn btn--ghost" onClick={() => clear(q)}>Clear answer</button> : null}
                  <button type="button" className="btn btn--primary" disabled={current >= questions.length - 1} onClick={() => setCurrent(current + 1)}>Next</button>
                </span>
              </div>
            </>
          ) : <p className="sub2">No question on this paper.</p>}
        </section>
        <aside className="card" style={{ padding: 16, alignSelf: "start", position: "sticky", top: 70 }}>
          <div className="sub2 mb-2">Questions · click to jump</div>
          <div style={{ display: "grid", gridTemplateColumns: "repeat(5, 1fr)", gap: 6 }}>
            {questions.map((x, i) => {
              const done = (answers[x.id] ?? []).length > 0;
              return <button key={x.id} type="button" onClick={() => setCurrent(i)} aria-label={`Question ${x.n}${done ? ", answered" : ""}`} className="tnum" style={{ padding: "6px 0", borderRadius: 6, border: `1px solid ${i === current ? "var(--ink, #10233b)" : "var(--line, #d9dee5)"}`, background: done ? "var(--green-ink, #1b7f3b)" : "#fff", color: done ? "#fff" : "inherit", fontWeight: i === current ? 700 : 400, cursor: "pointer" }}>{x.n}</button>;
            })}
          </div>
          <div className="sub2 mt-2">{answered} answered · {questions.length - answered} unanswered</div>
          <div className="sub2 mt-2">Violations recorded: <b className="tnum">{(warn?.violations ?? room.attempt.violations)}</b> of {room.exam.violation_limit} allowed</div>
        </aside>
      </main>

      {warn ? (
        <div role="alertdialog" aria-modal="true" style={{ position: "fixed", inset: 0, background: "rgba(0,0,0,0.55)", display: "grid", placeItems: "center", zIndex: 20 }}>
          <div className="card" style={{ maxWidth: 520, padding: 24, borderTop: `6px solid ${warn.level === "FINAL_WARNING" ? "#b3261e" : "#c77700"}` }}>
            <h2 style={{ marginTop: 0 }}>{warn.level === "FINAL_WARNING" ? "FINAL WARNING" : "WARNING"}</h2>
            {warn.level === "FINAL_WARNING"
              ? <p>Your examination session has recorded multiple violations ({warn.violations} of {warn.limit} allowed). Any further violation may result in {room.exam.violation_action === "TERMINATE" ? "automatic termination" : room.exam.violation_action === "SUBMIT" ? "automatic submission" : "action under"} University examination policy.</p>
              : <p>You have left the examination screen. This activity has been recorded ({warn.violations} of {warn.limit} allowed). Please return to the examination immediately.</p>}
            <button type="button" className="btn btn--primary" onClick={() => { setWarn(null); if (!document.fullscreenElement) void returnToFullscreen(); }}>Return to the examination</button>
          </div>
        </div>
      ) : null}
      {confirming ? (
        <div role="dialog" aria-modal="true" style={{ position: "fixed", inset: 0, background: "rgba(0,0,0,0.55)", display: "grid", placeItems: "center", zIndex: 20 }}>
          <div className="card" style={{ maxWidth: 520, padding: 24 }}>
            <h2 style={{ marginTop: 0 }}>Submit the examination?</h2>
            <p>{answered} of {questions.length} answered{questions.length - answered ? `; ${questions.length - answered} unanswered` : ""}. Once submitted, the attempt cannot be reopened. {unsaved ? `${unsaved} answer${unsaved === 1 ? "" : "s"} still saving will be sent first.` : ""}</p>
            {problem ? <p className="sub2">{problem.title}</p> : null}
            <div className="row row--inline row--tight">
              <button type="button" className="btn btn--ghost" disabled={busy} onClick={() => setConfirming(false)}>Keep writing</button>
              <button type="button" className="btn btn--go" disabled={busy} onClick={() => void submit(false)}>{busy ? "Submitting…" : "Submit now"}</button>
            </div>
          </div>
        </div>
      ) : null}
      <span hidden>{router ? "" : ""}</span>
    </div>
  );
}

function Screen({ title, children }: { title?: string; children: React.ReactNode }) {
  return (
    <div style={{ minHeight: "100vh", display: "grid", placeItems: "center", padding: 24, background: "var(--paper, #f6f7f9)" }}>
      <div className="card" style={{ maxWidth: 640, padding: 28 }}>
        {title ? <h1 style={{ marginTop: 0 }}>{title}</h1> : null}
        <div style={{ display: "grid", gap: 12 }}>{children}</div>
      </div>
    </div>
  );
}
