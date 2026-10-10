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
import { MathText } from "@/components/proto/MathText";
import { CbtImage } from "./CbtImage";

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

/** V371: how a candidate's paper differs from the office's preview of it */
interface PreviewNotes { selection: string; total_questions: number | null; pool_size: number; randomize_questions: boolean; randomize_options: boolean; paper_problem: string | null }
type NavFilter = "ALL" | "UNANSWERED" | "MARKED";
/** the question text sizes a candidate may choose, remembered on this browser only */
const TEXT_SIZES = [0.9, 1, 1.15, 1.3, 1.5];
const TEXT_SIZE_KEY = "cbt-text-size";
const OFFICE_HOME: Record<string, string> = { GST: "/gst/cbt", EPS: "/eps/cbt", EXAMS: "/exams/cbt", JUPEB: "/jupeb/cbt" };
/** V372: where the answers not yet saved are kept on this device, and for how long they are worth sending again */
const keptKey = (attemptId: string) => `cbt-unsaved:${attemptId}`;
const KEPT_FOR_MS = 2 * 24 * 3600 * 1000;

/** previewExamId (V371): the office opens its own paper in the room — no attempt, nothing saved, nothing reported, nothing submitted */
export function ExamRoom({ attemptId, apiBase = "/api/bff/api/v1/me/cbt", listHref = "/student/cbt", listLabel = "CBT examinations", previewExamId }: {
  attemptId: string; apiBase?: string; listHref?: string; listLabel?: string; previewExamId?: string;
}) {
  const preview = !!previewExamId;
  const [phase, setPhase] = useState<Phase>("loading");
  const [previewNotes, setPreviewNotes] = useState<PreviewNotes | null>(null);
  const [restoredCount, setRestoredCount] = useState(0);
  const [navFilter, setNavFilter] = useState<NavFilter>("ALL");
  const [textSize, setTextSize] = useState<number>(() => {
    try { const v = Number(window.localStorage.getItem(TEXT_SIZE_KEY)); return TEXT_SIZES.includes(v) ? v : 1; } catch { return 1; }
  });
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
  /* V376: the token as state too, for the images the page draws (a ref is not read while drawing) */
  const [imageToken, setImageToken] = useState<string | null>(null);
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
  // the current question's number kept in view inside the navigator (which scrolls on its own on a wide screen) — never the page
  const navGridRef = useRef<HTMLDivElement | null>(null);
  useEffect(() => {
    const grid = navGridRef.current;
    const btn = grid?.querySelector<HTMLElement>('[aria-current="step"]');
    if (!grid || !btn || grid.scrollHeight <= grid.clientHeight) return;
    if (btn.offsetTop < grid.scrollTop) grid.scrollTop = btn.offsetTop - 6;
    else if (btn.offsetTop + btn.offsetHeight > grid.scrollTop + grid.clientHeight) grid.scrollTop = btn.offsetTop + btn.offsetHeight - grid.clientHeight + 6;
  }, [current]);

  const exam = room?.exam;
  // V371: a preview goes back to the examination's own page on its office's desk
  const backHref = preview ? (exam?.office && OFFICE_HOME[exam.office] ? `${OFFICE_HOME[exam.office]}/${previewExamId}` : "/") : listHref;
  const backLabel = preview ? "the examination" : listLabel;
  const detectors = useMemo(() => new Set<Detector>(exam?.detectors ?? ALL_DETECTORS), [exam?.detectors]);
  const allowBack = exam?.allow_back !== false;
  const allowReview = exam?.allow_review !== false;
  const fullscreenRequired = exam?.fullscreen_required !== false;
  const proctored = exam?.proctoring === "CAMERA";

  const headers = useCallback((): HeadersInit => ({ "Content-Type": "application/json", "X-Attempt-Token": token.current ?? "" }), []);
  /* V376: an image on the paper — inside the attempt, with its token; in the office's preview, through the question's bank */
  const imageSrc = (image: string) => (preview ? `/api/bff/api/v1/cbt/questions/images/${image}` : `${apiBase}/attempts/${attemptId}/images/${image}`);

  const stopCamera = useCallback(() => {
    streamRef.current?.getTracks().forEach((t) => t.stop());
    streamRef.current = null;
    setCameraOn(false);
  }, []);

  const end = useCallback((status: string) => {
    setEndStatus(status);
    setPhase("ended");
    try { window.localStorage.removeItem(keptKey(attemptId)); } catch { /* nothing kept */ }
    stopCamera();
    if (document.fullscreenElement) document.exitFullscreen().catch(() => undefined);
  }, [stopCamera, attemptId]);

  /* the answers not yet saved, kept on this device for this attempt: a crash, a dead battery or a reload while offline loses none
     of them — they are sent again when the room reopens, and the save numbers keep an older one from replacing a newer */
  const keepUnsaved = useCallback(() => {
    if (preview) return;
    try {
      if (!pending.current.size) window.localStorage.removeItem(keptKey(attemptId));
      else window.localStorage.setItem(keptKey(attemptId), JSON.stringify({ at: Date.now(), items: Object.fromEntries(pending.current) }));
    } catch { /* storage refused: the answers wait in memory as before */ }
  }, [attemptId, preview]);

  const handleProblem = useCallback((p: Problem): boolean => {
    const code = (p as { code?: string }).code;
    if (code === "CBT_SESSION_REPLACED") { setPhase("replaced"); stopCamera(); return true; }
    if (code === "CBT_ATTEMPT_CLOSED") { end("CLOSED"); return true; }
    return false;
  }, [end, stopCamera]);

  /* ── the paper ── */
  const load = useCallback(async () => {
    if (!previewExamId) {
      try { token.current = sessionStorage.getItem(tokenKey(attemptId)); } catch { token.current = null; }
      if (!token.current) { setPhase("noToken"); return; }
    }
    // V371: a preview reads the office's own paper; there is no attempt and no token
    const r = previewExamId
      ? await fetch(`/api/bff/api/v1/cbt/exams/${encodeURIComponent(previewExamId)}/preview`)
      : await fetch(`${apiBase}/attempts/${attemptId}`, { headers: headers() });
    const j = await r.json().catch(() => null);
    if (!r.ok) { const p = (j as Problem) ?? { status: r.status, title: r.statusText }; if (!handleProblem(p)) { setProblem(p); setPhase("error"); } return; }
    const rm = j as Room;
    if (previewExamId) setPreviewNotes((j as { preview?: PreviewNotes }).preview ?? null);
    setRoom(rm);
    setImageToken(token.current);
    seqs.current = new Map(Object.entries(rm.seqs ?? {}).map(([k, v]) => [k, Number(v)]));
    // answers kept on this device and newer than the server's (by their save number) are restored and sent again
    const merged: Record<string, number[]> = { ...(rm.answers ?? {}) };
    const marks = new Set(rm.flagged ?? []);
    let restored = 0;
    if (!previewExamId) {
      try {
        const raw = window.localStorage.getItem(keptKey(attemptId));
        const kept = raw ? (JSON.parse(raw) as { at?: number; items?: Record<string, Pending> }) : null;
        if (kept && (!kept.at || Date.now() - kept.at > KEPT_FOR_MS)) window.localStorage.removeItem(keptKey(attemptId));
        else if (kept?.items) {
          for (const [qid, p] of Object.entries(kept.items)) {
            if (!p || typeof p.seq !== "number" || !rm.questions.some((x) => x.id === qid) || p.seq <= (seqs.current.get(qid) ?? 0)) continue;
            pending.current.set(qid, p);
            seqs.current.set(qid, p.seq);
            if (p.a) { if (p.a.length) merged[qid] = p.a; else delete merged[qid]; }
            if (p.flag !== undefined) { if (p.flag) marks.add(qid); else marks.delete(qid); }
            restored++;
          }
          if (!restored) window.localStorage.removeItem(keptKey(attemptId));
        }
      } catch { /* nothing kept, or storage refused */ }
    }
    setAnswers(merged);
    setFlagged([...marks]);
    if (restored) { setUnsaved(pending.current.size); setRestoredCount(restored); }
    setOffset(new Date(rm.now).getTime() - Date.now());
    setEndsAt(new Date(rm.attempt.ends_at).getTime());
    // a forward-only paper resumes at the first question not yet answered
    if (rm.exam.allow_back === false) {
      const firstOpen = rm.questions.findIndex((q) => !(rm.answers?.[q.id] ?? []).length);
      setCurrent(firstOpen < 0 ? Math.max(0, rm.questions.length - 1) : firstOpen);
    }
    if (rm.attempt.status !== "IN_PROGRESS") { end(rm.attempt.status); return; }
    setPhase("gate");
  }, [attemptId, apiBase, headers, handleProblem, end, previewExamId]);
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
    if (preview) return; // V371: a preview reports nothing
    const t = Date.now();
    if (!always && t - (lastReport.current.get(kind) ?? 0) < EVENT_GAP_MS) return;
    lastReport.current.set(kind, t);
    eventQueue.current.push({ kind, detail, n: currentRef.current + 1, ms: ms == null ? undefined : Math.max(0, Math.round(ms)) });
    void flushEvents();
  }, [flushEvents, preview]);

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
      if (!preview && (phaseRef.current === "writing" || phaseRef.current === "summary") && endsAtRef.current && n + offsetRef.current >= endsAtRef.current) void submitRef.current(true);
    }, 1000);
    return () => window.clearInterval(id);
  }, [report, preview]);
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
          keepUnsaved();
        }
        setUnsaved(pending.current.size);
        return false;
      }
      for (const b of batch) if (pending.current.get(b.q)?.seq === b.seq) pending.current.delete(b.q);
      keepUnsaved();
      setUnsaved(pending.current.size);
      if (j && j.status && j.status !== "IN_PROGRESS") end(j.status);
      return true;
    } catch {
      setUnsaved(pending.current.size);
      return false;
    }
  }, [attemptId, apiBase, headers, handleProblem, end, keepUnsaved]);

  const queueSave = (q: string, patch: Omit<Pending, "seq">) => {
    if (preview) return; // V371: a preview saves nothing
    const seq = (seqs.current.get(q) ?? 0) + 1;
    seqs.current.set(q, seq);
    pending.current.set(q, { ...pending.current.get(q), ...patch, seq });
    keepUnsaved();
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
    if (preview || (phase !== "writing" && phase !== "summary")) return;
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
      // V372: the answers not yet saved go too, as the page goes; they are also kept on the device in case this does not arrive
      if (pending.current.size) {
        const batch = [...pending.current.entries()].map(([q, p]) => ({ q, ...(p.a ? { a: p.a } : {}), ...(p.flag === undefined ? {} : { flag: p.flag }), seq: p.seq }));
        try { void fetch(`${apiBase}/attempts/${attemptId}/answers`, { method: "PUT", keepalive: true, headers: headers(), body: JSON.stringify({ answers: batch }) }); } catch { /* kept on the device */ }
      }
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
  }, [phase, detectors, fullscreenRequired, report, flushAnswers, flushEvents, apiBase, attemptId, headers, preview]);

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
  useEffect(() => { if (preview || (phase !== "writing" && phase !== "summary")) return; const id = window.setInterval(() => void heartbeat(), HEARTBEAT_MS); return () => window.clearInterval(id); }, [phase, heartbeat, preview]);

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
    if (preview) { end("PREVIEW"); return; } // V371: a preview is closed, never submitted
    setBusy(true);
    try {
      await flushAnswers();
      const r = await fetch(`${apiBase}/attempts/${attemptId}/submit`, { method: "POST", headers: headers(), body: "{}" });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const p = (j as Problem) ?? { status: r.status, title: r.statusText }; if (!handleProblem(p)) { if (auto) end("TIME_EXPIRED"); else setProblem(p); } return; }
      end(j.status ?? "SUBMITTED");
    } catch { if (auto) end("TIME_EXPIRED"); else setProblem({ status: 0, title: "The submission could not reach the server. Stay on this screen; it will retry." }); }
    finally { setBusy(false); }
  }, [attemptId, apiBase, headers, handleProblem, end, flushAnswers, preview]);
  useEffect(() => { submitRef.current = submit; }, [submit]);
  // answers restored from this device are sent as soon as the candidate is back on the paper
  useEffect(() => { if (phase === "writing" && pending.current.size) void flushAnswers(); }, [phase, flushAnswers]);

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
    if (preview) { setPhase("writing"); return; } // V371: no camera, no fullscreen, nothing reported
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
  /* the next question with no answer after this one — round to the start where the paper lets the candidate go back */
  const isOpen = (x: RoomQuestion) => !(answers[x.id] ?? []).length;
  const nextUnanswered = (() => {
    for (let k = current + 1; k < questions.length; k++) if (isOpen(questions[k])) return k;
    if (allowBack) for (let k = 0; k < current; k++) if (isOpen(questions[k])) return k;
    return -1;
  })();
  const shown = questions.map((x, i) => ({ x, i })).filter(({ x }) => navFilter === "ALL" || (navFilter === "UNANSWERED" ? isOpen(x) : flagged.includes(x.id)));
  const setSize = (step: number) => setTextSize((was) => TEXT_SIZES[Math.min(TEXT_SIZES.length - 1, Math.max(0, TEXT_SIZES.indexOf(was) + step))] ?? 1);
  useEffect(() => { try { window.localStorage.setItem(TEXT_SIZE_KEY, String(textSize)); } catch { /* remembered for this visit only */ } }, [textSize]);

  /* the keyboard on a computer: A–E choose an option, ← → previous and next, M marks for review. Up and down are left to the
     browser, which moves between a question's options; nothing is taken while a warning is on screen or a key is held. */
  const keysRef = useRef<(e: KeyboardEvent) => void>(() => undefined);
  const onKeys = (e: KeyboardEvent) => {
    if (phase !== "writing" || warn || e.repeat || e.ctrlKey || e.metaKey || e.altKey || !q) return;
    const t = e.target as HTMLElement | null;
    if (t && (t.tagName === "TEXTAREA" || (t.tagName === "INPUT" && !["radio", "checkbox"].includes((t as HTMLInputElement).type)) || t.isContentEditable)) return;
    const key = e.key.length === 1 ? e.key.toUpperCase() : e.key;
    if (key >= "A" && key <= "E" && key.length === 1) {
      const idx = key.charCodeAt(0) - 65;
      if (q.options[idx]) { e.preventDefault(); choose(q, q.options[idx].i); }
    } else if (key === "ArrowRight") {
      e.preventDefault();
      if (current < questions.length - 1) go(current + 1);
    } else if (key === "ArrowLeft") {
      e.preventDefault();
      if (allowBack) go(current - 1);
    } else if (key === "M" && allowReview) {
      e.preventDefault();
      toggleFlag(q);
    }
  };
  useEffect(() => { keysRef.current = onKeys; });
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => keysRef.current(e);
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  if (phase === "loading") return <Screen><p className="sub2">Opening your examination…</p></Screen>;
  if (phase === "noToken") return <Screen title="This screen does not hold your attempt"><p>Open the examination again from your CBT examinations page; your attempt continues where it was.</p><a className="btn btn--primary" href={backHref}>{backLabel}</a></Screen>;
  if (phase === "replaced") return <Screen title="Your examination was opened elsewhere"><p>The attempt continues on the device where it was opened last. The second sign-in is on the record.</p><a className="btn btn--ghost" href={backHref}>Back to {backLabel}</a></Screen>;
  if (phase === "error") return <Screen title="The examination could not be opened"><p>{problem?.detail ?? problem?.title}</p><a className="btn btn--ghost" href={backHref}>Back to {backLabel}</a></Screen>;
  if (phase === "noCamera") return (
    <Screen title="This examination is sat with the camera on">
      <p>The examination&rsquo;s rules ask for the camera, with your consent, while you write. Without it no answer can be saved. Your choice is recorded; nothing else is.</p>
      <p className="sub2">If you did not consent or the camera failed, speak to the examination office, or try again.</p>
      <span className="row row--inline row--tight"><button type="button" className="btn btn--primary" onClick={() => setPhase("camera")}>Try again</button><a className="btn btn--ghost" href={backHref}>Back to {backLabel}</a></span>
    </Screen>
  );
  if (phase === "ended") {
    const words: Record<string, [string, string]> = {
      SUBMITTED: ["Examination submitted", "Your examination has been submitted successfully. Your result has been recorded and will be released according to University examination policy."],
      TIME_EXPIRED: ["Time expired", "The examination ended at the end of your time. Whatever you had answered has been submitted and recorded; your result will be released according to University examination policy."],
      TERMINATED: ["Examination ended", "Your examination was ended under the University's examination policy. The record is reviewed by the office."],
      CLOSED: ["Examination closed", "The examination was closed. Whatever you had answered has been submitted and recorded; your result will be released according to University examination policy."],
      PREVIEW: ["Preview closed", "Nothing was saved, no attempt was made and no candidate was affected."],
    };
    const [t, text] = words[endStatus] ?? ["Examination ended", "Your attempt is no longer open."];
    return <Screen title={t}><p>{text}</p><a className="btn btn--primary" href={backHref} onClick={() => { try { sessionStorage.removeItem(tokenKey(attemptId)); } catch { /* ignored */ } }}>Back to {backLabel}</a></Screen>;
  }
  if (!room || !exam) return <Screen><p className="sub2">…</p></Screen>;
  if (phase === "gate") {
    return (
      <Screen title={`${preview ? "PREVIEW · " : ""}${exam.course_code} · ${exam.title}`}>
        {preview ? <PreviewNote notes={previewNotes} /> : null}
        {room.candidate && !preview ? (
          <div className={css.idCard}>
            <CandidateId c={room.candidate} labelled className={css.idGrid} />
            {room.placement?.sitting ? <div className="sub2"><b>{room.placement.sitting}</b> · {room.placement.sitting_venue}{room.placement.seat_no ? <> · seat <b className="tnum">{room.placement.seat_no}</b></> : null}</div> : null}
            {room.placement?.extra_minutes ? <div className="sub2">Your time includes <b>{room.placement.extra_minutes} minutes&rsquo; extra time</b> granted by the examination office.</div> : null}
            <div className="sub2">Check that these are yours before you enter. If they are not, tell the invigilator and do not start.</div>
          </div>
        ) : null}
        <p>{room.attempt.questions} questions · {room.attempt.max_marks} marks · {preview ? <>{exam.duration_minutes} minutes for a candidate</> : <>your time ends at <b className="tnum">{new Date(room.attempt.ends_at).toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" })}</b> ({clock(left)} left)</>}.</p>
        <ul className="sub2" style={{ margin: 0, paddingLeft: 18 }}>
          {fullscreenRequired ? <li>The examination opens in fullscreen.</li> : null}
          {detectors.size ? <li>Leaving the examination screen is recorded; {exam.violation_limit} recorded violation{exam.violation_limit === 1 ? " is" : "s are"} allowed.</li> : null}
          {!allowBack ? <li>This paper moves forward only: once you move on, an earlier question is not changed.</li> : null}
          {Number(exam.negative_marks ?? 0) > 0 ? <li>A wrong answer costs {exam.negative_marks} mark{Number(exam.negative_marks) === 1 ? "" : "s"}; an unanswered question costs nothing.</li> : null}
          {proctored ? <li>The camera is used, with your consent, to report face signals to the office. No video is kept, no microphone is used.</li> : null}
          <li>Your answers are saved as you go.</li>
        </ul>
        {room.attempt.number > 1 || room.attempt.answered ? <p className="sub2">You return to the attempt as you left it: {room.attempt.answered} answered.</p> : null}
        <button type="button" className="btn btn--primary" onClick={() => void begin()}>{preview ? "OPEN THE PREVIEW" : "ENTER THE EXAMINATION"}</button>
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
          <div className={css.cand}><CandidateId c={room.candidate} className={css.idInline} /></div>
        </div>
        {preview ? <span className={css.previewMark}>PREVIEW</span> : null}
        <button type="button" className={`btn btn--go ${css.finishTop}`} disabled={busy} onClick={() => setPhase("summary")}>FINISH</button>
        <div className={`${css.timer}${low && !preview ? ` ${css.low}` : ""}`} aria-live="polite"><span className={css.timerLabel}>TIME LEFT</span>{clock(left)}</div>
      </header>
      <div className={css.progress} aria-hidden="true"><div style={{ width: `${percent}%` }} /></div>
      {/* on a phone the header has no room for the whole of it: name, number and level in full, beneath it */}
      {room.candidate && !preview ? <div className={css.idStrip}><CandidateId c={room.candidate} labelled /></div> : null}
      {preview ? <div role="status" className={`${css.banner} ${css.bannerInfo}`}><PreviewNote notes={previewNotes} /><a className="btn btn--ghost btn--sm" href={backHref}>Close the preview</a></div> : null}
      {offline ? <div role="status" className={`${css.banner} ${css.bannerWarn}`}>Connection interrupted. Your answers are kept on this screen and saved when the connection returns; the clock continues.</div> : null}
      {fullscreenLost ? <div role="status" className={`${css.banner} ${css.bannerBad}`}><span>You have exited fullscreen mode. This has been recorded.</span><button type="button" className="btn btn--primary btn--sm" onClick={() => void returnToFullscreen()}>Return to fullscreen</button></div> : null}
      {refused ? <div role="status" className={`${css.banner} ${css.bannerBad}`}><span>{refused}</span><button type="button" className="btn btn--ghost btn--sm" onClick={() => setRefused(null)}>Dismiss</button></div> : null}
      {cameraNote ? <div role="status" className={`${css.banner} ${css.bannerInfo}`}><span>{cameraNote}</span><button type="button" className="btn btn--ghost btn--sm" onClick={() => setCameraNote(null)}>Dismiss</button></div> : null}
      {restoredCount ? <div role="status" className={`${css.banner} ${css.bannerInfo}`}><span>{restoredCount} answer{restoredCount === 1 ? "" : "s"} you gave before the screen closed {restoredCount === 1 ? "was" : "were"} kept on this device and {unsaved ? (restoredCount === 1 ? "is being saved" : "are being saved") : (restoredCount === 1 ? "has been saved" : "have been saved")}.</span><button type="button" className="btn btn--ghost btn--sm" onClick={() => setRestoredCount(0)}>Dismiss</button></div> : null}

      {phase === "summary" ? (
        <div className={css.body}>
          <main className={css.paper}>
            <div className={css.qnum}>REVIEW AND SUBMIT</div>
            {room.candidate && !preview ? <div className="sub2 mt-1"><CandidateId c={room.candidate} className={css.idInline} /></div> : null}
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
            <p className="sub2">{preview ? "This is the review a candidate sees before submitting. In the preview nothing is submitted." : <>Once submitted, the attempt cannot be reopened.{unsaved ? ` ${unsaved} answer${unsaved === 1 ? "" : "s"} still saving will be sent first.` : ""}</>}</p>
            {problem ? <p className="sub2">{problem.title}</p> : null}
            <div className="row row--inline row--tight">
              <button type="button" className="btn btn--ghost" disabled={busy} onClick={() => setPhase("writing")}>Back to the paper</button>
              <button type="button" className="btn btn--go" disabled={busy} onClick={() => void submit(false)}>{preview ? "CLOSE THE PREVIEW" : busy ? "Submitting…" : "SUBMIT EXAM"}</button>
            </div>
          </main>
        </div>
      ) : (
        <>
          <div className={css.body}>
            <main className={css.paper} style={{ ["--qscale" as string]: String(textSize) }}>
              {q ? (
                <>
                  <div className={css.qhead}>
                    <span className={css.qnum}>QUESTION {q.n} OF {questions.length}</span>
                    <span>{q.marks} mark{q.marks === 1 ? "" : "s"}</span>
                    <span>{q.kind === "MULTI" ? (exam.partial_credit ? "Select every correct option · each right one earns a share, each wrong one costs a share" : "Select every correct option") : q.kind === "TRUE_FALSE" ? "True or false" : "Select one option"}</span>
                    {onFlag ? <span className={css.flagMark}>Marked for review</span> : null}
                  </div>
                  {/* V376: formulas drawn from the text, and the question's diagram */}
                  <div className={css.stem}><MathText text={q.stem} /></div>
                  {q.image ? <CbtImage src={imageSrc(q.image)} headers={preview ? undefined : { "X-Attempt-Token": imageToken ?? "" }} alt={`Diagram for question ${q.n}`} /> : null}
                  <div className={css.options} role={q.kind === "MULTI" ? "group" : "radiogroup"} aria-label={`Question ${q.n} options`}>
                    {q.options.map((o, idx) => {
                      const on = (answers[q.id] ?? []).includes(o.i);
                      return (
                        <label key={o.i} className={`${css.option}${on ? ` ${css.optionOn}` : ""}`}>
                          <input type={q.kind === "MULTI" ? "checkbox" : "radio"} name={`q-${q.id}`} checked={on} onChange={() => choose(q, o.i)} />
                          <span><span className={css.letter}>{String.fromCharCode(65 + idx)}.</span><MathText text={o.text} />
                            {o.image ? <CbtImage src={imageSrc(o.image)} headers={preview ? undefined : { "X-Attempt-Token": imageToken ?? "" }} alt={`Option ${String.fromCharCode(65 + idx)} image`} style={{ maxHeight: 220 }} /> : null}</span>
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
              <button type="button" className={`btn btn--secondary btn--sm mb-2 ${css.onlySmall}`} style={{ width: "100%" }} disabled={nextUnanswered < 0} onClick={() => go(nextUnanswered)}>{nextUnanswered < 0 ? "Every question is answered" : `Go to the next unanswered (question ${questions[nextUnanswered]?.n})`}</button>
              {/* which questions the grid shows: every one, the unanswered, or those marked for review */}
              <div className={css.navFilter} role="group" aria-label="Show questions">
                {([["ALL", `All ${questions.length}`], ["UNANSWERED", `Unanswered ${unanswered}`], ...(allowReview ? [["MARKED", `Marked ${flaggedOnPaper.length}`]] : [])] as [NavFilter, string][]).map(([f, label]) => (
                  <button key={f} type="button" aria-pressed={navFilter === f} className={navFilter === f ? css.navFilterOn : undefined} onClick={() => setNavFilter(f)}>{label}</button>
                ))}
              </div>
              <div className={css.navGrid} ref={navGridRef}>
                {shown.map(({ x, i }) => {
                  const done = (answers[x.id] ?? []).length > 0;
                  const fl = flagged.includes(x.id);
                  return (
                    <button key={x.id} type="button" disabled={!allowBack && i < current} onClick={() => go(i)} aria-current={i === current ? "step" : undefined}
                      aria-label={`Question ${x.n}${done ? ", answered" : ", unanswered"}${fl ? ", marked for review" : ""}`}
                      className={`${css.navBtn}${done ? ` ${css.navAnswered}` : ""}${fl ? ` ${css.navFlagged}` : ""}${i === current ? ` ${css.navCurrent}` : ""}`}>{x.n}</button>
                  );
                })}
                {!shown.length ? <span className="sub2" style={{ gridColumn: "1 / -1" }}>{navFilter === "UNANSWERED" ? "Every question is answered." : "No question is marked for review."}</span> : null}
              </div>
              <div className={css.legend}><span className={css.lgAnswered}>Answered</span><span>Unanswered</span><span className={css.lgCurrent}>Current</span>{allowReview ? <span className={css.lgFlagged}>Marked for review</span> : null}</div>
              <div className="sub2 mt-2">{answered} answered · {unanswered} unanswered{allowReview ? ` · ${flaggedOnPaper.length} marked` : ""}{preview ? " · nothing is saved in a preview" : unsaved ? ` · ${unsaved} saving…` : " · saved"}</div>
              <div className={css.textSize} role="group" aria-label="Question text size">
                <span className="sub2">Text size</span>
                <button type="button" className="btn btn--ghost btn--sm" disabled={textSize <= TEXT_SIZES[0]} aria-label="Smaller question text" onClick={() => setSize(-1)}>A−</button>
                <button type="button" className="btn btn--ghost btn--sm" disabled={textSize >= TEXT_SIZES[TEXT_SIZES.length - 1]} aria-label="Larger question text" onClick={() => setSize(1)}>A+</button>
              </div>
              <div className={`sub2 ${css.keysHint}`}>Keys: <kbd>A</kbd>–<kbd>E</kbd> choose · <kbd>←</kbd> <kbd>→</kbd> previous and next{allowReview ? <> · <kbd>M</kbd> mark for review</> : null}</div>
              {detectors.size && !preview ? <div className="sub2 mt-1">Violations recorded: <b className="tnum">{warn?.violations ?? room.attempt.violations}</b> of {exam.violation_limit} allowed</div> : null}
              <button type="button" className="btn btn--go mt-2" style={{ width: "100%" }} disabled={busy} onClick={() => { setNavOpen(false); setPhase("summary"); }}>Review and submit</button>
            </aside>
          </div>
          <footer className={css.controls}>
            <div className={css.ctlSecondary}>
              <button type="button" className={`btn btn--ghost btn--sm ${css.navToggle}`} aria-expanded={navOpen} onClick={() => setNavOpen(!navOpen)}>{navOpen ? "Close" : `Questions (${answered}/${questions.length})`}</button>
              {/* on a phone this lives in the Questions panel, so the bar stays two rows */}
              <button type="button" className={`btn btn--ghost btn--sm ${css.hideSmall}`} disabled={nextUnanswered < 0} onClick={() => go(nextUnanswered)}>{nextUnanswered < 0 ? "All answered" : "Next unanswered"}</button>
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

/** whose paper this is — the candidate's name, their number named for what it is, and a student's level — for the candidate to
 *  check and for an invigilator to read at a glance */
function CandidateId({ c, className, labelled }: { c: Room["candidate"]; className?: string; labelled?: boolean }) {
  if (!c) return null;
  const name = `${c.surname.toUpperCase()}, ${c.other_names}`;
  const parts: [string, string][] = [["Name", name], [c.number_label ?? "Number", c.number], ...(c.level ? [["Level", `${c.level} Level`] as [string, string]] : [])];
  // labelled: each part under its label (the entry screen, the phone's strip); otherwise one line: NAME · Matric No. X · 200 Level
  return (
    <span className={className}>
      {parts.map(([label, value], i) => (
        <span key={label} className={css.idPart}>
          {labelled ? <span className={css.idLabel}>{label}</span> : null}
          {!labelled && i === 1 ? <>{label} </> : null}
          <b className={i === 0 ? undefined : "tnum"}>{value}</b>
        </span>
      ))}
    </span>
  );
}

/** V371: what the office is looking at, and how a candidate's paper differs from it */
function PreviewNote({ notes }: { notes: PreviewNotes | null }) {
  const drawn = notes && notes.selection === "RANDOM" && notes.total_questions && notes.total_questions < notes.pool_size;
  return (
    <span>
      <b>Preview</b> — the paper as a candidate sees it. Nothing is saved, no attempt is made and nothing is reported.
      {notes ? <>
        {drawn ? ` Each candidate gets ${notes.total_questions} of these ${notes.pool_size} questions${notes.randomize_questions ? ", in their own order" : ""}.` : notes.randomize_questions ? " Each candidate gets these questions in their own order." : ""}
        {notes.randomize_options ? " The options are shuffled for each candidate." : ""}
        {notes.paper_problem ? ` The paper is not ready: ${notes.paper_problem.replace(/^[A-Z_]+:\s*/, "")}.` : ""}
      </> : null}
    </span>
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
