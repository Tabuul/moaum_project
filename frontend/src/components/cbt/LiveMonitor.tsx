"use client";
/** The live CBT monitor (V322): the counters and every candidate's state while the examination runs, refreshed by controlled polling —
 *  the counters and only the attempts and events that changed since the cursor the screen holds, never the whole list again and never
 *  a candidate's answers. Status, clock, candidate, violations, connection: what an invigilator needs, and nothing a marker needs. */
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Problem } from "@/lib/api";
import { ATTEMPT_WORD, EVENT_WORD, EXAM_WORD, SEVERITY_WORD, clock, liveStatus, num, whenAt, type Candidate, type CandidatePage, type Monitor, type MonitorEvent, type MonitorRow } from "@/lib/cbt";
import { CandidateModal } from "./CbtCandidates";

type Filter = "ALL" | "IN_PROGRESS" | "SUBMITTED" | "NOT_STARTED" | "DISCONNECTED" | "WARNED" | "CRITICAL" | "TERMINATED" | "TIME_EXPIRED";
interface Row { student_id: string; number: string; surname: string; other_names: string; attempt_id: string | null; attempt_status: string; started_at: string | null; ends_at: string | null; submitted_at: string | null; last_activity_at: string | null; violations: number; answered: number; questions: number | null; score: number | null; max_marks: number | null; percentage: number | null; grade: string | null; outcome: string | null; finished_reason: string | null; eligible: boolean }

const POLL_MS = 5000;

export function LiveMonitor({ examId, base, canManage }: { examId: string; base: string; canManage: boolean }) {
  const [m, setM] = useState<Monitor | null>(null);
  const [rows, setRows] = useState<Map<string, Row>>(new Map());
  const [events, setEvents] = useState<MonitorEvent[]>([]);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [filter, setFilter] = useState<Filter>("ALL");
  const [q, setQ] = useState("");
  const [paused, setPaused] = useState(false);
  const [open, setOpen] = useState<string | null>(null);
  const [offset, setOffset] = useState(0);
  /* the clock read once per tick, so a render is pure */
  const [now, setNow] = useState(() => Date.now());
  const cursor = useRef<string | null>(null);
  const loadedCandidates = useRef(false);

  const merge = useCallback((list: MonitorRow[]) => {
    setRows((prev) => {
      const next = new Map(prev);
      for (const r of list) {
        const old = next.get(r.student_id);
        next.set(r.student_id, {
          student_id: r.student_id, number: r.number, surname: r.surname, other_names: r.other_names, attempt_id: r.attempt_id, attempt_status: r.attempt_status, started_at: r.started_at,
          ends_at: r.ends_at, submitted_at: r.submitted_at, last_activity_at: r.last_activity_at, violations: r.violations, answered: r.answered, questions: r.questions, score: r.score,
          max_marks: r.max_marks, percentage: r.percentage, grade: r.grade, outcome: r.outcome, finished_reason: r.finished_reason, eligible: old?.eligible ?? true,
        });
      }
      return next;
    });
  }, []);

  const poll = useCallback(async () => {
    const r = await fetch(`/api/bff/api/v1/cbt/exams/${examId}/monitor${cursor.current ? `?since=${encodeURIComponent(cursor.current)}` : ""}`);
    const j = await r.json().catch(() => null);
    if (!r.ok) { setProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return; }
    const mon = j as Monitor;
    setProblem(null);
    setM(mon);
    setOffset(new Date(mon.now).getTime() - Date.now());
    merge(mon.rows);
    if (mon.events.length) setEvents((prev) => { const ids = new Set(prev.map((e) => e.id)); return [...mon.events.filter((e) => !ids.has(e.id)), ...prev].slice(0, 300); });
    cursor.current = mon.cursor;
  }, [examId, merge]);

  /* the registered candidates who have not started, once: a name on the list before any attempt exists */
  const loadCandidates = useCallback(async () => {
    if (loadedCandidates.current) return;
    loadedCandidates.current = true;
    for (let page = 1; page < 40; page++) {
      const r = await fetch(`/api/bff/api/v1/cbt/exams/${examId}/candidates?page=${page}&size=500&sort=name`);
      const j = (await r.json().catch(() => null)) as CandidatePage | null;
      if (!r.ok || !j) return;
      setRows((prev) => {
        const next = new Map(prev);
        for (const c of j.rows as Candidate[]) {
          if (next.has(c.student_id)) { const o = next.get(c.student_id) as Row; next.set(c.student_id, { ...o, eligible: c.eligible }); continue; }
          next.set(c.student_id, { student_id: c.student_id, number: c.number, surname: c.surname, other_names: c.other_names, attempt_id: c.attempt_id, attempt_status: c.attempt_status, started_at: c.started_at, ends_at: c.ends_at, submitted_at: c.submitted_at, last_activity_at: c.last_activity_at, violations: c.violations, answered: c.answered, questions: null, score: c.score, max_marks: c.max_marks, percentage: c.percentage, grade: c.grade, outcome: c.outcome, finished_reason: null, eligible: c.eligible });
        }
        return next;
      });
      if (page * 500 >= j.total) return;
    }
  }, [examId]);

  useEffect(() => { void poll().then(loadCandidates); }, [poll, loadCandidates]);
  useEffect(() => {
    if (paused) return;
    const id = window.setInterval(() => void poll(), POLL_MS);
    return () => window.clearInterval(id);
  }, [poll, paused]);
  useEffect(() => { const id = window.setInterval(() => setNow(Date.now()), 1000); return () => window.clearInterval(id); }, []);

  const serverNow = now + offset;
  const limit = m?.exam.violation_limit ?? 0;
  const list = useMemo(() => {
    const all = [...rows.values()];
    const needle = q.trim().toLowerCase();
    return all.map((r) => ({ r, st: liveStatus(r.attempt_status as Candidate["attempt_status"], r.last_activity_at, serverNow) }))
      .filter(({ r, st }) => filter === "ALL" || (filter === "DISCONNECTED" ? st === "DISCONNECTED" : filter === "WARNED" ? r.violations > 0 : filter === "CRITICAL" ? r.violations >= limit && limit > 0 : st === filter))
      .filter(({ r }) => !needle || `${r.surname} ${r.other_names} ${r.number}`.toLowerCase().includes(needle))
      .sort((a, b) => a.r.surname.localeCompare(b.r.surname) || a.r.other_names.localeCompare(b.r.other_names));
  }, [rows, filter, q, serverNow, limit]);
  const c = m?.counts;
  const e = m?.exam;

  return (
    <>
      <PageHead eyebrow={e ? <span className="tnum">{e.reference} · {e.course_code}</span> : null} title={e ? `${e.title} — LIVE` : "Live CBT monitor"}
        description={e ? `Window ${whenAt(e.starts_at)} to ${whenAt(e.ends_at)} · ${e.duration_minutes} minutes per candidate · ${e.violation_limit} violation${e.violation_limit === 1 ? "" : "s"} allowed, then ${e.violation_action === "TERMINATE" ? "the attempt is terminated" : e.violation_action === "SUBMIT" ? "the attempt is submitted" : "a final warning"}. Refreshes every ${POLL_MS / 1000} seconds with only what changed.` : "Loading…"}
        actions={<span className="row row--inline row--tight">
          {e ? <Pil kind={(EXAM_WORD[e.live_state] ?? ["", "grey"])[1]}>{(EXAM_WORD[e.live_state] ?? [e.live_state])[0]}</Pil> : null}
          <Btn kind="ghost" size="sm" onClick={() => setPaused(!paused)}>{paused ? "Resume refresh" : "Pause refresh"}</Btn>
          <LinkBtn kind="ghost" size="sm" href={`${base}/cbt/${examId}`}>Examination</LinkBtn>
        </span>} />
      {problem ? <ProblemNotice problem={problem} /> : null}
      <Tiles items={[
        ["CANDIDATES", num(c?.candidates), null, `${num(c?.eligible)} eligible`],
        ["WRITING", num(c?.in_progress), c?.in_progress ? "var(--green-ink)" : null, "In progress now"],
        ["SUBMITTED", num(c?.submitted), null, `${num(c?.time_expired)} at time expired`],
        ["NOT STARTED", num(c?.not_started), null, "No attempt yet"],
        ["DISCONNECTED", num(c?.disconnected), c?.disconnected ? "var(--red-ink)" : null, "No heartbeat for 60 s"],
        ["WARNINGS", num(c?.warned), c?.warned ? "var(--red-ink)" : null, "Candidates with a violation"],
        ["CRITICAL", num(c?.critical), c?.critical ? "var(--red-ink)" : null, `At or over the limit of ${limit}`],
        ["TERMINATED", num(c?.terminated), c?.terminated ? "var(--red-ink)" : null, "By policy or the office"],
      ]} />
      <Note kind="info" title="What the browser can and cannot report">The portal records what happens inside the examination page — the tab hidden, the window losing focus, fullscreen exited, the connection lost, a second sign-in — and warns, holds or ends the attempt by the examination&rsquo;s policy. A standard browser cannot tell that a candidate switched to another application or device; for that, the examination is run in the secure/kiosk environment or the CBT laboratory.</Note>
      <div className="grid grid--3">
        <div style={{ gridColumn: "span 2" }}>
          <Panel title="Candidate monitor" right={<span className="sub2">{list.length} shown · server time {new Date(serverNow).toLocaleTimeString("en-GB")}</span>}>
            <PBody>
              <div className="row row--inline row--tight" style={{ flexWrap: "wrap" }}>
                {(["ALL", "IN_PROGRESS", "SUBMITTED", "NOT_STARTED", "DISCONNECTED", "WARNED", "CRITICAL", "TERMINATED", "TIME_EXPIRED"] as Filter[]).map((k) => (
                  <Btn key={k} kind={filter === k ? "primary" : "ghost"} size="sm" onClick={() => setFilter(k)}>{k === "ALL" ? "All" : k === "WARNED" ? "Warning" : k === "CRITICAL" ? "Violation" : (ATTEMPT_WORD[k] ?? [k])[0]}</Btn>
                ))}
                <Field id="mon-q" label="Search"><input id="mon-q" className="ctl" value={q} onChange={(ev) => setQ(ev.target.value)} placeholder="Name or number" /></Field>
              </div>
            </PBody>
            <DTable noPrint pageSize={50} cols={["S/N|num", "Student", "Matric No", "Status|mid", "Started|mid", "Time left|mid", "Answered|num", "Violations|num", "Score|num", "|num"]} rows={list.map(({ r, st }, i) => {
              const left = r.attempt_status === "IN_PROGRESS" && r.ends_at ? Math.max(0, (new Date(r.ends_at).getTime() - serverNow) / 1000) : null;
              return [
                <span key="n" className="tnum sub2">{i + 1}</span>,
                <span key="s"><b>{r.surname}, {r.other_names}</b>{!r.eligible && !r.attempt_id ? <div className="sub2">not eligible</div> : null}</span>,
                <span key="m" className="tnum">{r.number}</span>,
                <Pil key="st" kind={(ATTEMPT_WORD[st] ?? ["", "grey"])[1]}>{r.violations > 0 && st === "IN_PROGRESS" ? "Warning" : (ATTEMPT_WORD[st] ?? [st])[0]}</Pil>,
                <span key="b" className="tnum sub2">{r.started_at ? new Date(r.started_at).toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" }) : "—"}</span>,
                <span key="t" className={`tnum${left != null && left < 300 ? " ink-red b600" : ""}`}>{left == null ? "—" : clock(left)}</span>,
                <span key="a" className="tnum">{r.attempt_id ? `${r.answered}${r.questions ? `/${r.questions}` : ""}` : "—"}</span>,
                <span key="v" className={`tnum${r.violations >= limit && limit > 0 ? " ink-red b600" : r.violations ? " ink-red" : ""}`}>{r.violations}</span>,
                <span key="sc" className="tnum">{r.percentage == null ? "—" : `${Number(r.percentage).toFixed(1)}% ${r.grade ?? ""}`}</span>,
                <Btn key="o" kind="ghost" size="sm" onClick={() => setOpen(r.student_id)}>Open</Btn>,
              ];
            })} texts={list.map(({ r }) => `${r.surname} ${r.other_names} ${r.number}`)} />
          </Panel>
        </div>
        <Panel title="Events" right={<span className="sub2">violations and endings, latest first</span>}>
          {events.length ? (
            <div style={{ maxHeight: 640, overflow: "auto" }}>
              {events.map((ev) => (
                <div key={ev.id} className="row" style={{ padding: "6px 12px", borderBottom: "1px solid var(--line)" }}>
                  <span className="tnum sub2" style={{ minWidth: 64 }}>{new Date(ev.at).toLocaleTimeString("en-GB")}</span>
                  <span style={{ minWidth: 0 }}>{ev.violation ? <Pil kind="bad">{EVENT_WORD[ev.kind] ?? ev.kind}</Pil> : <Pil kind={ev.kind === "TERMINATED" ? "bad" : "warn"}>{EVENT_WORD[ev.kind] ?? ev.kind}</Pil>}<div className="sub2">{ev.surname}, {ev.other_names} · {ev.number}{ev.question_no ? ` · question ${ev.question_no}` : ""}{ev.severity ? ` · ${SEVERITY_WORD[ev.severity][0].toLowerCase()} weight` : ""}{ev.detail ? ` · ${ev.detail}` : ""}</div></span>
                </div>
              ))}
            </div>
          ) : <PBody><div className="sub2">No violation recorded.</div></PBody>}
        </Panel>
      </div>
      {open ? <CandidateModal examId={examId} student={open} canManage={canManage} onClose={() => setOpen(null)} onChanged={() => void poll()} /> : null}
    </>
  );
}
