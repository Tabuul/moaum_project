"use client";
/** V733 · MBBS academic sessions, for the Academic Office, the Registry and the College — the University's master prompt of 12 November
 *  2026 (part A): every MBBS student standing in a session of their own (one behind the University's), every change (the matriculation
 *  number, programme, previous and new session, level, when, by whom, how it stood), and a student's session set by an office — any
 *  approved session on the calendar's rules, a repeated year included, or back to the University's — with the reason. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { Btn, KvGrid, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { Modal } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { day } from "@/lib/format";
import { approvalWords, whyWords, type StudySessionPage } from "@/app/student/StudySession";

export interface StudySessionsView {
  university: string | null;
  bySession: { session: string; students: number }[];
  standing: { id: string; matric_no: string | null; name: string; programme: string | null; current_level: number; session: string;
    level_when_set: number; set_at: string; set_office: string; approval: string; reason: string | null }[];
  changes: { at: string; student_id: string; matric_no: string | null; name: string; programme: string | null; from_session: string | null;
    to_session: string | null; level: number | null; office: string | null; approval: string; reason: string | null; by_name: string | null }[];
}

const SETTERS = ["academic", "registrar", "dregistrar", "provost", "collegesecretary", "mbbscoordinator", "super"];

/** how a change stood, as an office reads it (the student's dashboard says "Your own choice") */
function how(a: string): string {
  return a === "NOT_REQUIRED" ? "The student's choice" : approvalWords(a);
}

export function StudySessions({ view, search, actingOffice }: { view: StudySessionsView; search: string; actingOffice: string | null }) {
  const router = useRouter();
  const [q, setQ] = useState(search);
  const [number, setNumber] = useState("");
  const [found, setFound] = useState<StudySessionPage | null>(null);
  const [pick, setPick] = useState("");
  const [reason, setReason] = useState("");
  const [confirm, setConfirm] = useState(false);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);
  const maySet = SETTERS.includes(actingOffice ?? "");

  async function find() {
    if (!number.trim()) return;
    setErr(null);
    setFound(null);
    const r = await fetch(`/api/bff/api/v1/study-sessions/student?number=${encodeURIComponent(number.trim())}`, { cache: "no-store" });
    const j = await r.json().catch(() => null);
    if (!r.ok) { const p: Problem = j ?? { status: r.status, title: r.statusText }; setErr(p); notifyProblem(p); return; }
    setFound(j as StudySessionPage);
    setPick("");
    setReason("");
  }

  async function save() {
    if (!found || busy) return;
    setBusy(true);
    setErr(null);
    try {
      const target = pick === "UNIVERSITY" ? null : pick;
      const studentId = (found.student as unknown as { id: string }).id;
      const r = await fetch(`/api/bff/api/v1/study-sessions/${encodeURIComponent(studentId)}`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Academic session set for ${found.student.name}`) },
        body: JSON.stringify({ session: target, reason: reason.trim() }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const p: Problem = j ?? { status: r.status, title: r.statusText }; setErr(p); notifyProblem(p); return; }
      setFound(j as StudySessionPage);
      setConfirm(false);
      setPick("");
      setReason("");
      notify(`${found.student.name}'s session set`);
      router.refresh();
    } finally {
      setBusy(false);
    }
  }

  const officeOptions = found ? found.options.filter((o) => !o.is_own && (o.selectable || o.why === "BEHIND_YOUR_REGISTRATION" || o.why === "LEVEL_REGISTERED_ELSEWHERE")) : [];
  const total = view.bySession.reduce((a, b) => a + Number(b.students), 0);
  return (
    <>
      <Note kind="info" title="MBBS students stand in a session of their own">
        The College runs MBBS behind the University&rsquo;s calendar (the University is in <b>{view.university ?? "—"}</b>). A student chooses an approved session on
        their dashboard and confirms it; registration, school fees, GST/EPS, examination permits and results follow it, and the level never changes with it. An office
        sets a session the student&rsquo;s rules refuse (a repeated year, a registration to move behind), with the reason. Every change is recorded below.
      </Note>
      {err ? <ProblemNotice problem={err} /> : null}
      <Tiles cls="grid--4" items={[
        ["In a session of their own", total.toLocaleString(), null, "The rest stand in the University's"],
        ...view.bySession.slice(0, 3).map((b) => [b.session, Number(b.students).toLocaleString(), null, b.session === view.university ? "The University's session" : "Behind the University"] as [string, string, null, string]),
      ]} />

      <Panel title="A student's session" right={maySet ? "Find by matriculation or admission number" : "Read only for your office"}>
        <PBody>
          <div className="row row--inline row--tight" style={{ gap: 8, flexWrap: "wrap" }}>
            <input className="ctl" placeholder="Matriculation number" value={number} onChange={(e) => setNumber(e.target.value)} onKeyDown={(e) => { if (e.key === "Enter") void find(); }} />
            <Btn kind="ghost" disabled={!number.trim()} onClick={() => void find()}>Find</Btn>
          </div>
          {found ? (
            <div className="mt-1">
              <KvGrid pairs={[
                ["Student", `${found.student.name} · ${found.student.matric_no ?? "—"}`],
                ["Programme", found.student.programme ?? "—"],
                ["Level", `${found.student.current_level} Level`],
                ["Session now", <span key="s"><b>{found.session}</b> {found.own ? <Pil kind="info">own</Pil> : <Pil kind="grey">the University&rsquo;s</Pil>}</span>],
              ]} />
              {!found.eligible ? <Note kind="info" title="This student stands in the University's session">{found.refusal === "NOT_COLLEGE_PROGRAMME" ? "Only a programme the College runs on its own calendar (MBBS) has sessions of its own." : `Not open to this record (${found.refusal}).`}</Note> : null}
              {found.eligible && maySet ? (
                <div className="row row--inline row--tight mt-1" style={{ gap: 8, flexWrap: "wrap", alignItems: "flex-end" }}>
                  <label className="sub2" htmlFor="ss-set">Set the session
                    <select id="ss-set" className="ctl" value={pick} onChange={(e) => setPick(e.target.value)} style={{ display: "block", minWidth: 280 }}>
                      <option value="">Choose…</option>
                      {found.own ? <option value="UNIVERSITY">Back to the University&rsquo;s ({found.university})</option> : null}
                      {officeOptions.filter((o) => !o.is_university || !found.own).map((o) => (
                        <option key={o.session} value={o.is_university ? "UNIVERSITY" : o.session}>{o.session}{o.is_university ? " (the University's)" : ""}{o.why ? ` — ${whyWords(o.why)}` : ""}</option>
                      ))}
                    </select>
                  </label>
                  <input className="ctl" style={{ minWidth: 320 }} placeholder="Reason (ten characters or more)" value={reason} onChange={(e) => setReason(e.target.value)} maxLength={600} />
                  <Btn kind="primary" disabled={!pick || reason.trim().length < 10 || busy} onClick={() => setConfirm(true)}>Set</Btn>
                </div>
              ) : null}
              {found.history.length ? (
                <DTable cols={["When|mid", "From", "To", "Level|mid", "How", "By"]} rows={found.history.map((h, i) => [
                  <span key={`a${i}`} className="tnum">{day(h.at)}</span>, h.from_session ?? "The University's", h.to_session ?? "The University's",
                  h.level != null ? String(h.level) : "—", <span key={`h${i}`}>{how(h.approval)}{h.reason ? <div className="sub2">{h.reason}</div> : null}</span>, h.by_name ?? "—",
                ])} />
              ) : null}
            </div>
          ) : null}
        </PBody>
      </Panel>

      <Panel title="Students in a session of their own" right={
        <form className="row row--inline row--tight" onSubmit={(e) => { e.preventDefault(); router.push(`/college/study-sessions${q.trim() ? `?q=${encodeURIComponent(q.trim())}` : ""}`); }}>
          <input className="ctl" placeholder="Name or number" value={q} onChange={(e) => setQ(e.target.value)} />
          <Btn kind="ghost" type="submit">Search</Btn>
        </form>}>
        {view.standing.length ? (
          <DTable cols={["Student", "Programme", "Level|mid", "Session", "Set|mid", "How"]} rows={view.standing.map((s) => [
            <span key={s.id}><b>{s.name}</b><div className="sub2">{s.matric_no ?? "—"}</div></span>, s.programme ?? "—", `${s.current_level}`, s.session,
            <span key={`d${s.id}`} className="tnum">{day(s.set_at)}</span>, <span key={`w${s.id}`}>{how(s.approval)}{s.reason ? <div className="sub2">{s.reason}</div> : null}</span>,
          ])} />
        ) : <PBody><div className="sub2">No student stands in a session of their own{search ? " for that search" : ""}.</div></PBody>}
      </Panel>

      <Panel title="Every change" right={`${view.changes.length} shown, newest first`}>
        {view.changes.length ? (
          <DTable cols={["When|mid", "Student", "Programme", "From", "To", "Level|mid", "How", "By"]} rows={view.changes.map((c, i) => [
            <span key={`a${i}`} className="tnum">{day(c.at)}</span>, <span key={`s${i}`}><b>{c.name}</b><div className="sub2">{c.matric_no ?? "—"}</div></span>,
            c.programme ?? "—", c.from_session ?? "The University's", c.to_session ?? "The University's", c.level != null ? String(c.level) : "—",
            <span key={`h${i}`}>{how(c.approval)}{c.reason ? <div className="sub2">{c.reason}</div> : null}</span>, c.by_name ?? "—",
          ])} />
        ) : <PBody><div className="sub2">No change yet.</div></PBody>}
      </Panel>

      {confirm && found ? (
        <Modal title={`Set ${found.student.name}'s session?`} onClose={() => { if (!busy) setConfirm(false); }}
          foot={<div className="row row--inline row--tight row--right" style={{ gap: 8 }}>
            <Btn kind="ghost" disabled={busy} onClick={() => setConfirm(false)}>Cancel</Btn>
            <Btn kind="primary" disabled={busy} onClick={() => void save()}>{busy ? "Saving…" : "Set the session"}</Btn>
          </div>}>
          <PBody>
            <KvGrid cls="grid--3" pairs={[
              ["Previous academic session", found.session],
              ["New academic session", <b key="n">{pick === "UNIVERSITY" ? found.university : pick}</b>],
              ["Current academic level", `${found.student.current_level} Level`],
            ]} />
            <div className="sub2 mt-1">Reason: {reason.trim()}</div>
          </PBody>
        </Modal>
      ) : null}
    </>
  );
}
