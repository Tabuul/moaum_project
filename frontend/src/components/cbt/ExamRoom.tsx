"use client";
/** The examination room (V322; V364 for every screen and every examination's own settings): one attempt, the server's clock, the paper as
 *  it was drawn for this candidate, the answers saved as the candidate goes — each save numbered, so a late retry over a poor connection
 *  never overwrites a newer answer — questions marked for review, a forward-only paper where the examination says so, and the browser's
 *  reports the examination asks for, sent to the server, which warns or ends the attempt by its own thresholds. A proctored examination asks
 *  for the candidate's consent before the camera is used; no video is kept. The paper arrives without its keys; the screen never has them.
 *  A standard browser cannot stop a candidate switching to another application or device, and this screen does not pretend to: it reports
 *  what it can see. */
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import type { Problem } from "@/lib/api";
import { DEFAULT_INSTITUTION } from "@/lib/document/institution";
import { clock, type Detector, type Room, type RoomQuestion } from "@/lib/cbt";
import { tokenKey } from "./MyExams";
import css from "./ExamRoom.module.css";

type Phase = "loading" | "gate" | "camera" | "writing" | "summary" | "ended" | "replaced" | "noToken" | "noCamera" | "error";
interface Warn { level: "WARNING" | "FINAL_WARNING"; violations: number; limit: number }
interface Pending { a?: number[]; flag?: boolean; seq: number }
interface Ev { kind: string; detail?: string; n?: number; ms?: number }
interface FaceDetectorLike { detect(src: CanvasImageSource): Promise<{ boundingBox: DOMRectReadOnly }[]> }

const HEARTBEAT_MS = 30_000;
const SAVE_DEBOUNCE_MS = 1200;
/** one report of the same kind in this long: a burst of blur events is one event */
const EVENT_GAP_MS = 10_000;
const ALL_DETECTORS: Detector[] = ["TAB", "BLUR", "FULLSCREEN", "COPY", "PASTE", "RIGHT_CLICK", "NETWORK"];
const FACE_EVERY_MS = 3000;

export function ExamRoom({ attemptId, apiBase = "/api/bff/api/v1/me/cbt", listHref = "/student/cbt", listLabel = "CBT examinations" }: {
  attemptId: string; apiBase?: string; listHref?: string; listLabel?: string;
}) {
  const [phase, setPhase] = useState<Phase>("loading");
  const [room, setRoom] = useState<Room | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [answers, setAnswers] = useState<Record<string, number[]>>({});
  const [flagged, setFlagged] = useState<string[]>([]);
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
  const [busy, setBusy] = useState(false);
  const [navOpen, setNavOpen] = useState(false);
  const [refused, setRefused] = useState<string | null>(null);
  const [cameraOn, setCameraOn] = useState(false);
  const [cameraNote, setCameraNote] = useState<string | null>(null);
  const token = useRef<string | null>(null);
  const pending = useRef<Map<string, Pending>>(new Map());
  const seqs = useRef<Map<string, number>>(new Map());
  const saveTimer = useRef<number | null>(null);
  const eventQueue = useRef<Ev[]>([]);
  const lastReport = useRef<Map<string, number>>(new Map());
  const hiddenAt = useRef<number | null>(null);
  const blurredAt = useRef<number | null>(null);
  const offlineAt = useRef<number | null>(null);
  const fullscreenOutAt = useRef<number | null>(null);
  const phaseRef = useRef<Phase>("loading");
  const endsAtRef = useRef(0);
  const offsetRef = useRef(0);
  const currentRef = useRef(0);
  const clock0 = useRef<{ wall: number; perf: number } | null>(null);
  const submitRef = useRef<(auto: boolean) => Promise<void>>(async () => undefined);
  const videoRef = useRef<HTMLVideoElement | null>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const noFaceSince = useRef<number | null>(null);
  const awayReported = useRef(false);
  useEffect(() => { phaseRef.current = phase; }, [phase]);
  useEffect(() => { endsAtRef.current = endsAt; }, [endsAt]);
  useEffect(() => { offsetRef.current = offset; }, [offset]);
  useEffect(() => { currentRef.current = current; }, [current]);

  const exam = room?.exam;
  const detectors = useMemo(() => new Set<Detector>(exam?.detectors ?? ALL_DETECTORS), [exam?.detectors]);
  const allowBack = exam?.allow_back !== false;
  const allowReview = exam?.allow_review !== false;
  const fullscreenRequired = exam?.fullscreen_required !== false;
  const proctored = exam?.proctoring === "CAMERA";

  const headers = useCallback((): HeadersInit => ({ "Content-Type": "application/json", "X-Attempt-Token": token.current ?? "" }), []);

  const stopCamera = useCallback(() => {
    streamRef.current?.getTracks().forEach((t) => t.stop());
    streamRef.current = null;
    setCameraOn(false);
  }, []);

  const end = useCallback((status: string) => {
    setEndStatus(status);
    setPhase("ended");
    stopCamera();
    if (document.fullscreenElement) document.exitFullscreen().catch(() => undefined);
  }, [stopCamera]);

  const handleProblem = useCallback((p: Problem): boolean => {
    const code = (p as { code?: string }).code;
    if (code === "CBT_SESSION_REPLACED") { setPhase("replaced"); stopCamera(); return true; }
    if (code === "CBT_ATTEMPT_CLOSED") { end("CLOSED"); return true; }
    return false;
  }, [end, stopCamera]);

  /* ── the paper ── */
  const load = useCallback(async () => {
    try { token.current = sessionStorage.getItem(tokenKey(attemptId)); } catch { token.current = null; }
    if (!token.current) { setPhase("noToken"); return; }
    const r = await fetch(`${apiBase}/attempts/${attemptId}`, { headers: headers() });
    const j = await r.json().catch(() => null);
    if (!r.ok) { const p = (j as Problem) ?? { status: r.status, title: r.statusText }; if (!handleProblem(p)) { setProblem(p); setPhase("error"); } return; }
    const rm = j as Room;
    setRoom(rm);
    setAnswers(rm.answers ?? {});
    setFlagged(rm.flagged ?? []);
    seqs.current = new Map(Object.entries(rm.seqs ?? {}).map(([k, v]) => [k, Number(v)]));
    setOffset(new Date(rm.now).getTime() - Date.now());
    setEndsAt(new Date(rm.attempt.ends_at).getTime());
    // a forward-only paper resumes at the first question not yet answered
    if (rm.exam.allow_back === false) {
      const firstOpen = rm.questions.findIndex((q) => !(rm.answers?.[q.id] ?? []).length);
      setCurrent(firstOpen < 0 ? Math.max(0, rm.questions.length - 1) : firstOpen);
    }
    if (rm.attempt.status !== "IN_PROGRESS") { end(rm.attempt.status); return; }
    setPhase("gate");
  }, [attemptId, apiBase, headers, handleProblem, end]);
  useEffect(() => { const t = window.setTimeout(() => void load(), 0); return () => window.clearTimeout(t); }, [load]);

  /* ── the browser's reports ── */
  const flushEvents = useCallback(async () => {
    if (!eventQueue.current.length || (phaseRef.current !== "writing" && phaseRef.current !== "summary")) return;
    const batch = eventQueue.current.splice(0, eventQueue.current.length);
    try {
      const r = await fetch(`${apiBase}/attempts/${attemptId}/events`, { method: "POST", headers: headers(), body: JSON.stringify({ events: batch }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const p = (j as Problem) ?? { status: r.status, title: r.statusText }; if (!handleProblem(p)) eventQueue.current.unshift(...batch); return; }
      if (j.action === "SUBMITTED" || j.action === "TERMINATED") { end(j.action); return; }
      if (j.level) setWarn({ level: j.level, violations: Number(j.violations), limit: Number(j.limit) });
    } catch { eventQueue.current.unshift(...batch); }
  }, [attemptId, apiBase, headers, handleProblem, end]);
  /** a report, at most one of a kind in a short span, naming the question the candidate was on */
  const report = useCallback((kind: string, detail?: string, ms?: number, always = false) => {
    const t = Date.now();
    if (!always && t - (lastReport.current.get(kind) ?? 0) < EVENT_GAP_MS) return;
    lastReport.current.set(kind, t);
    eventQueue.current.push({ kind, detail, n: currentRef.current + 1, ms: ms == null ? undefined : Math.max(0, Math.round(ms)) });
    void flushEvents();
  }, [flushEvents]);

  /* ── the server's clock, ticking locally; at the end of time the attempt submits itself; a device clock moved is reported ── */
  useEffect(() => {
    const id = window.setInterval(() => {
      const n = Date.now();
      setNow(n);
      const p = performance.now();
      if (!clock0.current) clock0.current = { wall: n, perf: p };
      const drift = (n - clock0.current.wall) - (p - clock0.current.perf);
      if (Math.abs(drift) > 120_000) {
        clock0.current = { wall: n, perf: p };
        if (phaseRef.current === "writing") report("TIME_MANIPULATION_ATTEMPT", `the device clock moved by ${Math.round(drift / 1000)}s; the server's clock stands`);
      }
      if ((phaseRef.current === "writing" || phaseRef.current === "summary") && endsAtRef.current && n + offsetRef.current >= endsAtRef.current) void submitRef.current(true);
    }, 1000);
    return () => window.clearInterval(id);
  }, [report]);
  const serverNow = now + offset;
  const left = Math.max(0, (endsAt - serverNow) / 1000);

  /* ── answers: debounced, batched, numbered, retried ── */
  const flushAnswers = useCallback(async (): Promise<boolean> => {
    if (!pending.current.size || (phaseRef.current !== "writing" && phaseRef.current !== "summary")) return true;
    const batch = [...pending.current.entries()].map(([q, p]) => ({ q, ...(p.a ? { a: p.a } : {}), ...(p.flag === undefined ? {} : { flag: p.flag }), seq: p.seq }));
    try {
      const r = await fetch(`${apiBase}/attempts/${attemptId}/answers`, { method: "PUT", headers: headers(), body: JSON.stringify({ answers: batch }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) {
        const p = (j as Problem) ?? { status: r.status, title: r.statusText };
        if (handleProblem(p)) return false;
        if (r.status >= 400 && r.status < 500) {
          // the server will not take these (a forward-only paper, an option out of range): kept off the retry, the candidate told
          for (const b of batch) if (pending.current.get(b.q)?.seq === b.seq) pending.current.delete(b.q);
          setRefused(p.title ?? "An answer was not saved.");
        }
        setUnsaved(pending.current.size);
        return false;
      }
      for (const b of batch) if (pending.current.get(b.q)?.seq === b.seq) pending.current.delete(b.q);
      setUnsaved(pending.current.size);
      if (j && j.status && j.status !== "IN_PROGRESS") end(j.status);
      return true;
    } catch {
      setUnsaved(pending.current.size);
      return false;
    }
  }, [attemptId, apiBase, headers, handleProblem, end]);

  const queueSave = (q: string, patch: Omit<Pending, "seq">) => {
    const seq = (seqs.current.get(q) ?? 0) + 1;
    seqs.current.set(q, seq);
    pending.current.set(q, { ...pending.current.get(q), ...patch, seq });
    setUnsaved(pending.current.size);
    if (saveTimer.current) window.clearTimeout(saveTimer.current);
    saveTimer.current = window.setTimeout(() => void flushAnswers(), SAVE_DEBOUNCE_MS);
  };
  const choose = (q: RoomQuestion, i: number) => {
    const was = answers[q.id] ?? [];
    const next = q.kind === "MULTI" ? (was.includes(i) ? was.filter((x) => x !== i) : [...was, i].sort((a, b) => a - b)) : [i];
    setAnswers({ ...answers, [q.id]: next });
    queueSave(q.id, { a: next });
  };
  const clear = (q: RoomQuestion) => {
    const n = { ...answers };
    delete n[q.id];
    setAnswers(n);
    queueSave(q.id, { a: [] });
  };
  const toggleFlag = (q: RoomQuestion) => {
    if (!allowReview) return;
    const on = !flagged.includes(q.id);
    setFlagged(on ? [...flagged, q.id] : flagged.filter((x) => x !== q.id));
    queueSave(q.id, { flag: on });
  };

  useEffect(() => {
    if (phase !== "writing" && phase !== "summary") return;
    const onVisibility = () => {
      if (!detectors.has("TAB")) return;
      if (document.visibilityState === "hidden") { hiddenAt.current = Date.now(); report("TAB_SWITCH", "the examination tab was hidden"); }
      else if (hiddenAt.current) { const ms = Date.now() - hiddenAt.current; hiddenAt.current = null; report("RESUMED", `back after ${Math.round(ms / 1000)}s`, ms, true); }
    };
    const onBlur = () => {
      if (!detectors.has("BLUR") || document.visibilityState === "hidden") return;
      blurredAt.current = Date.now();
      report("WINDOW_BLUR", "the examination window lost focus");
    };
    const onFocus = () => {
      if (!detectors.has("BLUR") || !blurredAt.current) return;
      const ms = Date.now() - blurredAt.current; blurredAt.current = null;
      if (ms > 1000) report("WINDOW_FOCUS", `focus back after ${Math.round(ms / 1000)}s`, ms, true);
    };
    const onFullscreen = () => {
      if (!document.fullscreenElement) {
        if (fullscreenRequired) setFullscreenLost(true);
        fullscreenOutAt.current = Date.now();
        if (detectors.has("FULLSCREEN")) report("FULLSCREEN_EXIT", "fullscreen was exited");
      } else {
        setFullscreenLost(false);
        if (fullscreenOutAt.current && detectors.has("FULLSCREEN")) { const ms = Date.now() - fullscreenOutAt.current; report("FULLSCREEN_ENTER", "back in fullscreen", ms, true); }
        fullscreenOutAt.current = null;
      }
    };
    const onOffline = () => {
      setOffline(true); offlineAt.current = Date.now();
      if (detectors.has("NETWORK")) eventQueue.current.push({ kind: "NETWORK_DISCONNECT", detail: "the browser went offline", n: currentRef.current + 1 });
    };
    const onOnline = () => {
      setOffline(false);
      const ms = offlineAt.current ? Date.now() - offlineAt.current : undefined; offlineAt.current = null;
      if (detectors.has("NETWORK")) report("RECONNECTED", "the browser is back online", ms, true);
      void flushAnswers(); void flushEvents();
    };
    const onCopy = (e: ClipboardEvent) => { if (!detectors.has("COPY")) return; e.preventDefault(); report(e.type === "cut" ? "CUT_ATTEMPT" : "COPY_ATTEMPT"); };
    const onPaste = (e: ClipboardEvent) => { if (!detectors.has("PASTE")) return; e.preventDefault(); report("PASTE_ATTEMPT"); };
    const onContext = (e: Event) => { if (!detectors.has("RIGHT_CLICK")) return; e.preventDefault(); report("RIGHT_CLICK"); };
    /* leaving the page: told to the server even as the page goes, the attempt kept for the candidate's return */
    const onLeave = () => {
      try { void fetch(`${apiBase}/attempts/${attemptId}/events`, { method: "POST", keepalive: true, headers: headers(), body: JSON.stringify({ events: [{ kind: "EXAM_PAGE_EXIT", detail: "the examination page was left or reloaded", n: currentRef.current + 1 }] }) }); } catch { /* the page is going */ }
    };
    document.addEventListener("visibilitychange", onVisibility);
    window.addEventListener("blur", onBlur);
    window.addEventListener("focus", onFocus);
    document.addEventListener("fullscreenchange", onFullscreen);
    window.addEventListener("offline", onOffline);
    window.addEventListener("online", onOnline);
    document.addEventListener("copy", onCopy); document.addEventListener("cut", onCopy); document.addEventListener("paste", onPaste);
    document.addEventListener("contextmenu", onContext);
    window.addEventListener("pagehide", onLeave);
    return () => {
      document.removeEventListener("visibilitychange", onVisibility); window.removeEventListener("blur", onBlur); window.removeEventListener("focus", onFocus);
      document.removeEventListener("fullscreenchange", onFullscreen); window.removeEventListener("offline", onOffline); window.removeEventListener("online", onOnline);
      document.removeEventListener("copy", onCopy); document.removeEventListener("cut", onCopy); document.removeEventListener("paste", onPaste);
      document.removeEventListener("contextmenu", onContext); window.removeEventListener("pagehide", onLeave);
    };
  }, [phase, detectors, fullscreenRequired, report, flushAnswers, flushEvents, apiBase, attemptId, headers]);

  /* ── the heartbeat: the server's word on the attempt every half minute, and a retry of anything unsaved ── */
  const heartbeat = useCallback(async () => {
    if (phaseRef.current !== "writing" && phaseRef.current !== "summary") return;
    await flushAnswers();
    await flushEvents();
    try {
      const r = await fetch(`${apiBase}/attempts/${attemptId}/ping`, { method: "POST", headers: headers(), body: "{}" });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const p = (j as Problem) ?? { status: r.status, title: r.statusText }; handleProblem(p); return; }
      setOffset(new Date(j.now).getTime() - Date.now());
      if (j.endsAt) setEndsAt(new Date(j.endsAt).getTime());
      if (j.status !== "IN_PROGRESS") end(j.status);
      setOffline(false);
    } catch { setOffline(true); }
  }, [attemptId, apiBase, headers, handleProblem, end, flushAnswers, flushEvents]);
  useEffect(() => { if (phase !== "writing" && phase !== "summary") return; const id = window.setInterval(() => void heartbeat(), HEARTBEAT_MS); return () => window.clearInterval(id); }, [phase, heartbeat]);

  /* ── the camera, by consent: presence and, where the browser can see faces, face signals — never a recording ── */
  useEffect(() => {
    if (!cameraOn || (phase !== "writing" && phase !== "summary")) return;
    const Detector = (window as unknown as { FaceDetector?: new (o?: { fastMode?: boolean; maxDetectedFaces?: number }) => FaceDetectorLike }).FaceDetector;
    if (!Detector) return;
    let detector: FaceDetectorLike | null = null;
    try { detector = new Detector({ fastMode: true, maxDetectedFaces: 3 }); } catch { detector = null; }
    if (!detector) return;
    const id = window.setInterval(() => {
      const v = videoRef.current;
      if (!v || v.readyState < 2 || !detector) return;
      detector.detect(v).then((faces) => {
        const t = Date.now();
        if (faces.length === 0) {
          if (noFaceSince.current == null) noFaceSince.current = t;
          const gone = t - noFaceSince.current;
          if (gone >= 6000) report("FACE_NOT_DETECTED", "no face seen by the camera", gone);
          if (gone >= 20000 && !awayReported.current) { awayReported.current = true; report("PROLONGED_LOOK_AWAY", "no face seen for a prolonged time", gone, true); }
          return;
        }
        noFaceSince.current = null; awayReported.current = false;
        if (faces.length > 1) { report("MULTIPLE_FACES", `${faces.length} faces seen by the camera`); return; }
        const b = faces[0].boundingBox, w = v.videoWidth || 1, cx = (b.x + b.width / 2) / w;
        if (cx < 0.15 || cx > 0.85) report("FACE_OUT_OF_FRAME", "the face is at the edge of the camera's view");
      }).catch(() => undefined);
    }, FACE_EVERY_MS);
    return () => window.clearInterval(id);
  }, [cameraOn, phase, report]);
  useEffect(() => () => { streamRef.current?.getTracks().forEach((t) => t.stop()); }, []);

  async function camera(consent: boolean): Promise<boolean> {
    try {
      const r = await fetch(`${apiBase}/attempts/${attemptId}/camera`, { method: "POST", headers: headers(), body: JSON.stringify({ consent }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const p = (j as Problem) ?? { status: r.status, title: r.statusText }; if (!handleProblem(p)) setProblem(p); return false; }
      return true;
    } catch { setProblem({ status: 0, title: "The portal could not be reached; try again." }); return false; }
  }
  async function consentAndStart() {
    setBusy(true); setProblem(null);
    try {
      let stream: MediaStream;
      try { stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: "user", width: 320, height: 240 }, audio: false }); }
      catch { await camera(false); setPhase("noCamera"); return; }
      streamRef.current = stream;
      if (!(await camera(true))) { stopCamera(); return; }
      stream.getVideoTracks().forEach((t) => { t.onended = () => { setCameraOn(false); report("CAMERA_STOPPED", "the camera stopped", undefined, true); }; });
      setCameraOn(true);
      if (!("FaceDetector" in window)) setCameraNote("This browser reports only whether the camera is on; face signals need a browser that can see faces, or the University's proctoring tool.");
      await enter();
    } finally { setBusy(false); }
  }
  async function decline() {
    setBusy(true);
    try { await camera(false); setPhase("noCamera"); } finally { setBusy(false); }
  }
  useEffect(() => {
    if (cameraOn && videoRef.current && streamRef.current && videoRef.current.srcObject !== streamRef.current) {
      videoRef.current.srcObject = streamRef.current;
      void videoRef.current.play().catch(() => undefined);
    }
  });

  /* ── the end of time, or the candidate's submission: what was saved first, then the server's word ── */
  const submit = useCallback(async (auto: boolean) => {
    if (phaseRef.current !== "writing" && phaseRef.current !== "summary") return;
    setBusy(true);
    try {
      await flushAnswers();
      const r = await fetch(`${apiBase}/attempts/${attemptId}/submit`, { method: "POST", headers: headers(), body: "{}" });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const p = (j as Problem) ?? { status: r.status, title: r.statusText }; if (!handleProblem(p)) { if (auto) end("TIME_EXPIRED"); else setProblem(p); } return; }
      end(j.status ?? "SUBMITTED");
    } catch { if (auto) end("TIME_EXPIRED"); else setProblem({ status: 0, title: "The submission could not reach the server. Stay on this screen; it will retry." }); }
    finally { setBusy(false); }
  }, [attemptId, apiBase, headers, handleProblem, end, flushAnswers]);
  useEffect(() => { submitRef.current = submit; }, [submit]);

  /* fullscreen asked for, but never waited on for long: a browser that refuses or never answers still lets the candidate write */
  const goFullscreen = () => Promise.race([
    document.documentElement.requestFullscreen?.() ?? Promise.resolve(),
    new Promise<void>((resolve) => window.setTimeout(resolve, 1500)),
  ]).catch(() => undefined);
  async function enter() {
    if (fullscreenRequired) await goFullscreen();
    setPhase("writing");
    report("RESUMED", "the examination screen was entered", undefined, true);
  }
  const begin = async () => {
    if (proctored && !room?.attempt.camera_consent_at && !cameraOn) { setPhase("camera"); return; }
    if (proctored && !cameraOn) { await consentAndStart(); return; }
    await enter();
  };
  const returnToFullscreen = async () => { await goFullscreen(); if (document.fullscreenElement) setFullscreenLost(false); };

  const questions = useMemo(() => room?.questions ?? [], [room]);
  const q = questions[current];
  const answered = useMemo(() => questions.filter((x) => (answers[x.id] ?? []).length > 0).length, [questions, answers]);
  const unanswered = questions.length - answered;
  const flaggedOnPaper = questions.filter((x) => flagged.includes(x.id));
  const low = left < 300;
  const go = (i: number) => {
    if (i < 0 || i >= questions.length) return;
    if (!allowBack && i < current) return;
    setCurrent(i);
    setNavOpen(false);
    if (typeof window !== "undefined") window.scrollTo({ top: 0, behavior: "smooth" });
  };

  if (phase === "loading") return <Screen><p className="sub2">Opening your examination…</p></Screen>;
  if (phase === "noToken") return <Screen title="This screen does not hold your attempt"><p>Open the examination again from your CBT examinations page; your attempt continues where it was.</p><a className="btn btn--primary" href={listHref}>{listLabel}</a></Screen>;
  if (phase === "replaced") return <Screen title="Your examination was opened elsewhere"><p>The attempt continues on the browser or device where it was opened last. This screen no longer holds it, and the second sign-in is on the record.</p><a className="btn btn--ghost" href={listHref}>Back to {listLabel}</a></Screen>;
  if (phase === "error") return <Screen title="The examination could not be opened"><p>{problem?.detail ?? problem?.title}</p><a className="btn btn--ghost" href={listHref}>Back to {listLabel}</a></Screen>;
  if (phase === "noCamera") return (
    <Screen title="This examination is sat with the camera on">
      <p>The examination&rsquo;s rules ask for the camera, with your consent, while you write. Without it no answer can be saved. Your choice is recorded; nothing else is.</p>
      <p className="sub2">If you did not consent, or your camera could not be used, speak to the examination office: they decide how you may sit it. You may also try again.</p>
      <span className="row row--inline row--tight"><button type="button" className="btn btn--primary" onClick={() => setPhase("camera")}>Try again</button><a className="btn btn--ghost" href={listHref}>Back to {listLabel}</a></span>
    </Screen>
  );
  if (phase === "ended") {
    const words: Record<string, [string, string]> = {
      SUBMITTED: ["Examination submitted", "Your examination has been submitted successfully. Your result has been recorded and will be released according to University examination policy."],
      TIME_EXPIRED: ["Time expired", "The examination ended at the end of your time. Whatever you had answered has been submitted and recorded; your result will be released according to University examination policy."],
      TERMINATED: ["Examination ended", "Your examination was ended under the University's examination policy. The record is reviewed by the office."],
      CLOSED: ["Examination closed", "The examination was closed. Whatever you had answered has been submitted and recorded; your result will be released according to University examination policy."],
    };
    const [t, text] = words[endStatus] ?? ["Examination ended", "Your attempt is no longer open."];
    return <Screen title={t}><p>{text}</p><a className="btn btn--primary" href={listHref} onClick={() => { try { sessionStorage.removeItem(tokenKey(attemptId)); } catch { /* ignored */ } }}>Back to {listLabel}</a></Screen>;
  }
  if (!room || !exam) return <Screen><p className="sub2">…</p></Screen>;
  if (phase === "gate") {
    return (
      <Screen title={`${exam.course_code} · ${exam.title}`}>
        <p>{room.attempt.questions} questions · {room.attempt.max_marks} marks · your time ends at <b className="tnum">{new Date(room.attempt.ends_at).toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" })}</b> ({clock(left)} left).</p>
        <ul className="sub2" style={{ margin: 0, paddingLeft: 18 }}>
          {fullscreenRequired ? <li>The examination opens in fullscreen.</li> : null}
          {detectors.size ? <li>Leaving the examination screen is recorded; {exam.violation_limit} recorded violation{exam.violation_limit === 1 ? " is" : "s are"} allowed.</li> : null}
          {!allowBack ? <li>This paper moves forward only: once you move on, an earlier question is not changed.</li> : null}
          {Number(exam.negative_marks ?? 0) > 0 ? <li>A wrong answer costs {exam.negative_marks} mark{Number(exam.negative_marks) === 1 ? "" : "s"}; an unanswered question costs nothing.</li> : null}
          {proctored ? <li>The camera is used, with your consent, to report face signals to the office. No video is kept, no microphone is used.</li> : null}
          <li>Your answers are saved as you go.</li>
        </ul>
        {room.attempt.number > 1 || room.attempt.answered ? <p className="sub2">You return to the attempt as you left it: {room.attempt.answered} answered.</p> : null}
        <button type="button" className="btn btn--primary" onClick={() => void begin()}>ENTER THE EXAMINATION</button>
      </Screen>
    );
  }
  if (phase === "camera") {
    return (
      <Screen title="Your consent to the camera">
        <p>This examination is proctored by camera. With your consent, the examination screen uses your camera while you write and reports to the examination office when it sees no face, more than one face, or a face at the edge of its view.</p>
        <ul className="sub2" style={{ margin: 0, paddingLeft: 18 }}>
          <li>No video and no picture is recorded or sent; only those signals, with the time.</li>
          <li>The microphone is not used. Nobody is identified by their face.</li>
          <li>A signal is evidence for the office to review under University policy, never a finding on its own.</li>
          <li>Without your consent no answer can be saved; the office decides how you may sit the examination.</li>
        </ul>
        {problem ? <p className="sub2">{problem.title}</p> : null}
        <span className="row row--inline row--tight">
          <button type="button" className="btn btn--primary" disabled={busy} onClick={() => void consentAndStart()}>{busy ? "Starting the camera…" : "I CONSENT — START THE CAMERA"}</button>
          <button type="button" className="btn btn--ghost" disabled={busy} onClick={() => void decline()}>I do not consent</button>
        </span>
      </Screen>
    );
  }

  const name = room.candidate ? `${room.candidate.surname.toUpperCase()}, ${room.candidate.other_names}` : "";
  const percent = questions.length ? Math.round((answered / questions.length) * 100) : 0;
  const onFlag = q ? flagged.includes(q.id) : false;
  const last = current >= questions.length - 1;

  return (
    <div className={css.room}>
      <header className={css.bar}>
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img className={css.crest} src="/crest.png" alt="" />
        <div className={css.who}>
          <div className={css.uni}>{DEFAULT_INSTITUTION.name}</div>
          <div className={css.exam}><b>{exam.course_code}</b> · {exam.title}</div>
          <div className={css.cand}>{name}{room.candidate ? <> · <span className="tnum">{room.candidate.number}</span></> : null}</div>
        </div>
        <button type="button" className={`btn btn--go ${css.finishTop}`} disabled={busy} onClick={() => setPhase("summary")}>FINISH</button>
        <div className={`${css.timer}${low ? ` ${css.low}` : ""}`} aria-live="polite"><span className={css.timerLabel}>TIME LEFT</span>{clock(left)}</div>
      </header>
      <div className={css.progress} aria-hidden="true"><div style={{ width: `${percent}%` }} /></div>
      {offline ? <div role="status" className={`${css.banner} ${css.bannerWarn}`}>Connection interrupted. Your exam session is being preserved. Please reconnect. Your answers are kept on this screen and saved when the connection returns; the clock continues.</div> : null}
      {fullscreenLost ? <div role="status" className={`${css.banner} ${css.bannerBad}`}><span>You have exited fullscreen mode. This has been recorded.</span><button type="button" className="btn btn--primary btn--sm" onClick={() => void returnToFullscreen()}>Return to fullscreen</button></div> : null}
      {refused ? <div role="status" className={`${css.banner} ${css.bannerBad}`}><span>{refused}</span><button type="button" className="btn btn--ghost btn--sm" onClick={() => setRefused(null)}>Dismiss</button></div> : null}
      {cameraNote ? <div role="status" className={`${css.banner} ${css.bannerInfo}`}><span>{cameraNote}</span><button type="button" className="btn btn--ghost btn--sm" onClick={() => setCameraNote(null)}>Dismiss</button></div> : null}

      {phase === "summary" ? (
        <div className={css.body}>
          <main className={css.paper}>
            <div className={css.qnum}>REVIEW AND SUBMIT</div>
            <div className={css.summaryGrid}>
              <div className={css.summaryTile}><b>{questions.length}</b>Questions</div>
              <div className={css.summaryTile}><b>{answered}</b>Answered</div>
              <div className={css.summaryTile}><b>{unanswered}</b>Unanswered</div>
              <div className={css.summaryTile}><b>{flaggedOnPaper.length}</b>Marked for review</div>
            </div>
            {unanswered ? <p><b>You have {unanswered} unanswered question{unanswered === 1 ? "" : "s"}. Are you sure you want to submit?</b></p> : <p>Every question is answered.</p>}
            {allowBack && (unanswered || flaggedOnPaper.length) ? (
              <div className="mb-2">
                {unanswered ? <div className="sub2 mb-1">Unanswered: {questions.filter((x) => !(answers[x.id] ?? []).length).map((x) => <button key={x.id} type="button" className="btn btn--ghost btn--sm" style={{ margin: 2 }} onClick={() => { setPhase("writing"); go(questions.indexOf(x)); }}>{x.n}</button>)}</div> : null}
                {flaggedOnPaper.length ? <div className="sub2">Marked for review: {flaggedOnPaper.map((x) => <button key={x.id} type="button" className="btn btn--ghost btn--sm" style={{ margin: 2 }} onClick={() => { setPhase("writing"); go(questions.indexOf(x)); }}>{x.n}</button>)}</div> : null}
              </div>
            ) : null}
            <p className="sub2">Once submitted, the attempt cannot be reopened.{unsaved ? ` ${unsaved} answer${unsaved === 1 ? "" : "s"} still saving will be sent first.` : ""}</p>
            {problem ? <p className="sub2">{problem.title}</p> : null}
            <div className="row row--inline row--tight">
              <button type="button" className="btn btn--ghost" disabled={busy} onClick={() => setPhase("writing")}>Back to the paper</button>
              <button type="button" className="btn btn--go" disabled={busy} onClick={() => void submit(false)}>{busy ? "Submitting…" : "SUBMIT EXAM"}</button>
            </div>
          </main>
        </div>
      ) : (
        <>
          <div className={css.body}>
            <main className={css.paper}>
              {q ? (
                <>
                  <div className={css.qhead}>
                    <span className={css.qnum}>QUESTION {q.n} OF {questions.length}</span>
                    <span>{q.marks} mark{q.marks === 1 ? "" : "s"}</span>
                    <span>{q.kind === "MULTI" ? (exam.partial_credit ? "Select every correct option · each right one earns a share, each wrong one costs a share" : "Select every correct option") : q.kind === "TRUE_FALSE" ? "True or false" : "Select one option"}</span>
                    {onFlag ? <span className={css.flagMark}>Marked for review</span> : null}
                  </div>
                  <div className={css.stem}>{q.stem}</div>
                  <div className={css.options} role={q.kind === "MULTI" ? "group" : "radiogroup"} aria-label={`Question ${q.n} options`}>
                    {q.options.map((o, idx) => {
                      const on = (answers[q.id] ?? []).includes(o.i);
                      return (
                        <label key={o.i} className={`${css.option}${on ? ` ${css.optionOn}` : ""}`}>
                          <input type={q.kind === "MULTI" ? "checkbox" : "radio"} name={`q-${q.id}`} checked={on} onChange={() => choose(q, o.i)} />
                          <span><span className={css.letter}>{String.fromCharCode(65 + idx)}.</span>{o.text}</span>
                        </label>
                      );
                    })}
                  </div>
                </>
              ) : <p className="sub2">No question on this paper.</p>}
            </main>
            <aside className={`${css.nav}${navOpen ? ` ${css.navOpen}` : ""}`} aria-label="Question navigator">
              <div className="row row--inline row--tight mb-2" style={{ justifyContent: "space-between" }}>
                <span className="sub2">{allowBack ? "Questions · tap to go to one" : "Questions · this paper moves forward only"}</span>
                <button type="button" className={`btn btn--ghost btn--sm ${css.navToggle}`} onClick={() => setNavOpen(false)}>Close</button>
              </div>
              <div className={css.navGrid}>
                {questions.map((x, i) => {
                  const done = (answers[x.id] ?? []).length > 0;
                  const fl = flagged.includes(x.id);
                  return (
                    <button key={x.id} type="button" disabled={!allowBack && i < current} onClick={() => go(i)} aria-current={i === current ? "step" : undefined}
                      aria-label={`Question ${x.n}${done ? ", answered" : ", unanswered"}${fl ? ", marked for review" : ""}`}
                      className={`${css.navBtn}${done ? ` ${css.navAnswered}` : ""}${fl ? ` ${css.navFlagged}` : ""}${i === current ? ` ${css.navCurrent}` : ""}`}>{x.n}</button>
                  );
                })}
              </div>
              <div className={css.legend}><span className={css.lgAnswered}>Answered</span><span>Unanswered</span><span className={css.lgCurrent}>Current</span>{allowReview ? <span className={css.lgFlagged}>Marked for review</span> : null}</div>
              <div className="sub2 mt-2">{answered} answered · {unanswered} unanswered{allowReview ? ` · ${flaggedOnPaper.length} marked` : ""}{unsaved ? ` · ${unsaved} saving…` : " · saved"}</div>
              {detectors.size ? <div className="sub2 mt-1">Violations recorded: <b className="tnum">{warn?.violations ?? room.attempt.violations}</b> of {exam.violation_limit} allowed</div> : null}
              <button type="button" className="btn btn--go mt-2" style={{ width: "100%" }} disabled={busy} onClick={() => { setNavOpen(false); setPhase("summary"); }}>Review and submit</button>
            </aside>
          </div>
          <footer className={css.controls}>
            <div className={css.ctlSecondary}>
              <button type="button" className={`btn btn--ghost btn--sm ${css.navToggle}`} aria-expanded={navOpen} onClick={() => setNavOpen(!navOpen)}>{navOpen ? "Close" : `Questions (${answered}/${questions.length})`}</button>
              {q && (answers[q.id] ?? []).length ? <button type="button" className="btn btn--ghost btn--sm" onClick={() => clear(q)}>Clear answer</button> : null}
              {q && allowReview ? <button type="button" className="btn btn--ghost btn--sm" aria-pressed={onFlag} onClick={() => toggleFlag(q)}>{onFlag ? "Unmark review" : "Mark for review"}</button> : null}
            </div>
            <div className={css.ctlPrimary}>
              {allowBack ? <button type="button" className="btn btn--ghost" disabled={current === 0} onClick={() => go(current - 1)}>Previous</button> : null}
              {last ? <button type="button" className="btn btn--go" disabled={busy} onClick={() => setPhase("summary")}>Review &amp; submit</button>
                : <button type="button" className="btn btn--primary" onClick={() => go(current + 1)}>Next</button>}
            </div>
          </footer>
        </>
      )}

      {cameraOn ? <div className={css.preview} aria-label="Your camera"><video ref={videoRef} muted playsInline autoPlay /></div> : null}

      {warn ? (
        <div role="alertdialog" aria-modal="true" className={css.dialogBack}>
          <div className={css.dialog} style={{ borderTop: `6px solid ${warn.level === "FINAL_WARNING" ? "#b3261e" : "#c77700"}` }}>
            <h2 style={{ marginTop: 0 }}>{warn.level === "FINAL_WARNING" ? "FINAL WARNING" : "WARNING"}</h2>
            {warn.level === "FINAL_WARNING"
              ? <p>Your examination session has recorded multiple violations ({warn.violations} of {warn.limit} allowed). Any further violation may result in {exam.violation_action === "TERMINATE" ? "automatic termination" : exam.violation_action === "SUBMIT" ? "automatic submission" : "action under"} University examination policy.</p>
              : <p>You have left the examination screen. This activity has been recorded ({warn.violations} of {warn.limit} allowed). Please return to the examination immediately.</p>}
            <button type="button" className="btn btn--primary" onClick={() => { setWarn(null); if (fullscreenRequired && !document.fullscreenElement) void returnToFullscreen(); }}>Return to the examination</button>
          </div>
        </div>
      ) : null}
    </div>
  );
}

function Screen({ title, children }: { title?: string; children: React.ReactNode }) {
  return (
    <div className={css.screen}>
      <div className={css.screenCard}>
        {title ? <h1>{title}</h1> : null}
        {children}
      </div>
    </div>
  );
}
