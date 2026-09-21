"use client";

/**
 * The postgraduate results desk (V211): the department / School sees the registrations for a session and
 * semester, endorses them (Head of Department), and records each course's continuous assessment and
 * examination marks — the total and grade (A/B/C/F) are computed. This is what lights up a student's
 * results, GPA and CGPA.
 */
import { useCallback, useEffect, useMemo, useState } from "react";
import { reasonHeader } from "@/lib/reason";
import type { Problem } from "@/lib/api";
import { Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";

interface Prog { code: string; name: string; faculty_name: string }
interface Reg {
  id: string; session: string; semester: number; mode: string; state: string; endorsed_at: string | null;
  surname: string; other_names: string; matric_no: string | null; admission_no: string | null;
  programme_name: string; programme_code: string; courses: number; gpa: number;
}
interface Entry { entry_id: string; code: string; title: string; units: number; kind: string; ca: number | null; exam: number | null; total: number | null; grade: string | null }
interface Detail { id: string; name: string; programme_name: string; mode: string; state: string; entries: Entry[] }

export function ResultsDesk({ initialSession, mayEdit }: { initialSession: string; mayEdit: boolean }) {
  const [progs, setProgs] = useState<Prog[]>([]);
  const [session, setSession] = useState(initialSession);
  const [semester, setSemester] = useState(1);
  const [programme, setProgramme] = useState("");
  const [regs, setRegs] = useState<Reg[]>([]);
  const [detail, setDetail] = useState<Detail | null>(null);
  const [scores, setScores] = useState<Record<string, { ca: string; exam: string }>>({});
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    let live = true;
    fetch("/api/bff/api/v1/pg/programmes").then((r) => (r.ok ? r.json() : [])).then((j) => { if (live) setProgs(Array.isArray(j) ? j : []); }).catch(() => {});
    return () => { live = false; };
  }, []);

  const loadRegs = useCallback(async (s: string, sem: number, p: string) => {
    const q = `session=${encodeURIComponent(s)}&semester=${sem}${p ? `&programme=${encodeURIComponent(p)}` : ""}`;
    const r = await fetch(`/api/bff/api/v1/pg/coursework/registrations?${q}`, { cache: "no-store" });
    setProblem(null);
    const j = await r.json().catch(() => null);
    if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
    setRegs(Array.isArray(j) ? (j as Reg[]) : []);
  }, []);

  useEffect(() => { void (async () => { await loadRegs(session, semester, programme); })(); }, [session, semester, programme, loadRegs]);

  const loadDetail = useCallback(async (id: string) => {
    const r = await fetch(`/api/bff/api/v1/pg/coursework/registrations/${id}`, { cache: "no-store" });
    setProblem(null);
    const j = await r.json().catch(() => null);
    if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
    const d = j as Detail;
    setDetail(d);
    const init: Record<string, { ca: string; exam: string }> = {};
    for (const e of d.entries) init[e.entry_id] = { ca: e.ca == null ? "" : String(e.ca), exam: e.exam == null ? "" : String(e.exam) };
    setScores(init);
  }, []);

  const byFaculty = useMemo(() => {
    const m = new Map<string, Prog[]>();
    for (const p of progs) { const k = p.faculty_name; if (!m.has(k)) m.set(k, []); m.get(k)!.push(p); }
    return [...m.entries()];
  }, [progs]);

  async function endorse() {
    if (!detail) return;
    setBusy(true); setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/pg/coursework/registrations/${detail.id}/endorse`, {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Endorsed ${detail.name}'s registration`) }, body: "{}",
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      setDetail(j as Detail);
      await loadRegs(session, semester, programme);
    } finally { setBusy(false); }
  }

  async function saveScore(entryId: string) {
    const s = scores[entryId];
    if (!s) return;
    setBusy(true); setProblem(null);
    try {
      const r = await fetch("/api/bff/api/v1/pg/coursework/score", {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Recorded score for entry ${entryId}`) },
        body: JSON.stringify({ entryId, ca: s.ca === "" ? null : Number(s.ca), exam: s.exam === "" ? null : Number(s.exam) }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      if (detail) await loadDetail(detail.id);
    } finally { setBusy(false); }
  }

  return (
    <>
      {problem ? <ProblemNotice problem={problem} /> : null}
      <Panel title="Registrations" right={
        <span style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
          <input className="ctl tnum" style={{ width: 110 }} value={session} onChange={(e) => setSession(e.target.value)} aria-label="Session" />
          <select className="ctl" style={{ width: "auto" }} value={semester} onChange={(e) => setSemester(Number(e.target.value))} aria-label="Semester">
            <option value={1}>First semester</option><option value={2}>Second semester</option>
          </select>
          <select className="ctl" style={{ width: "auto", maxWidth: 220 }} value={programme} onChange={(e) => setProgramme(e.target.value)} aria-label="Programme">
            <option value="">All programmes</option>
            {byFaculty.map(([fac, list]) => <optgroup key={fac} label={fac}>{list.map((p) => <option key={p.code} value={p.code}>{p.name}</option>)}</optgroup>)}
          </select>
        </span>
      }>
        {regs.length ? (
          <DTable cols={["Student", "Programme", "Mode|mid", "Courses|num", "GPA|num", "Status|mid", "|mid"]}
            rows={regs.map((r) => [
              <span key="n"><span style={{ fontWeight: 600 }}>{r.surname}, {r.other_names}</span><div className="sub2 tnum">{r.matric_no ?? r.admission_no ?? ""}</div></span>,
              <span key="p" className="sub2">{r.programme_name}</span>,
              <span key="m" className="sub2">{r.mode === "PART_TIME" ? "Part-time" : "Full-time"}</span>,
              <span key="c" className="tnum">{r.courses}</span>,
              <span key="g" className="tnum">{Number(r.gpa).toFixed(2)}</span>,
              r.state === "ENDORSED" ? <Pil key="s" kind="ok">Endorsed</Pil> : <Pil key="s" kind="info">{r.state.toLowerCase()}</Pil>,
              <button key="o" className="btn btn--ghost btn--sm" onClick={() => void loadDetail(r.id)}>Open</button>,
            ])} texts={regs.map((r) => `${r.surname} ${r.other_names} ${r.matric_no ?? ""} ${r.programme_name}`)} />
        ) : <PBody><div className="sub2">No registration for this session and semester.</div></PBody>}
      </Panel>

      {detail ? (
        <Panel title={`${detail.name} · ${detail.programme_name}`} right={<button className="btn btn--ghost btn--sm" onClick={() => setDetail(null)}>Close</button>}>
          <PBody>
            <div style={{ display: "flex", gap: 10, alignItems: "center", flexWrap: "wrap", marginBottom: 10 }}>
              <span className="sub2">{detail.mode === "PART_TIME" ? "Part-time" : "Full-time"}</span>
              {detail.state === "ENDORSED" ? <Pil kind="ok">Endorsed</Pil> : <Pil kind="info">{detail.state.toLowerCase()}</Pil>}
              {mayEdit && detail.state !== "ENDORSED" ? <button className="btn btn--primary btn--sm" disabled={busy} onClick={() => void endorse()}>Endorse registration</button> : null}
            </div>
            <DTable cols={["Course", "Title", "Units|num", "CA|mid", "Exam|mid", "Total|num", "Grade|mid", "|mid"]}
              rows={detail.entries.map((e) => {
                const s = scores[e.entry_id] ?? { ca: "", exam: "" };
                return [
                  <span key="c" className="tnum">{e.code}</span>, e.title, <span key="u" className="tnum">{e.units}</span>,
                  mayEdit ? <input key="ca" className="ctl tnum" style={{ width: 64 }} value={s.ca} onChange={(ev) => setScores({ ...scores, [e.entry_id]: { ...s, ca: ev.target.value.replace(/[^0-9.]/g, "") } })} /> : <span className="tnum">{e.ca ?? "—"}</span>,
                  mayEdit ? <input key="ex" className="ctl tnum" style={{ width: 64 }} value={s.exam} onChange={(ev) => setScores({ ...scores, [e.entry_id]: { ...s, exam: ev.target.value.replace(/[^0-9.]/g, "") } })} /> : <span className="tnum">{e.exam ?? "—"}</span>,
                  <span key="t" className="tnum">{e.total ?? "—"}</span>,
                  e.grade ? <Pil key="g" kind={e.grade === "F" ? "bad" : e.grade === "C" ? "warn" : "ok"}>{e.grade}</Pil> : <span key="g" className="sub2">—</span>,
                  mayEdit ? <button key="s" className="btn btn--go btn--sm" disabled={busy} onClick={() => void saveScore(e.entry_id)}>Save</button> : null,
                ];
              })} />
            <Note kind="info" title="Grading (Policy 16)">Continuous assessment is 30–40% and the examination 60–70%; the total gives A 70+, B 60–69, C 50–59, F below 50. There is no resit.</Note>
          </PBody>
        </Panel>
      ) : null}
    </>
  );
}
