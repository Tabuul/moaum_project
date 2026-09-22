"use client";

/**
 * The postgraduate student's course registration and results (V211). They register the courses their
 * programme carries for a session and semester (core, elective, research), and once the department has
 * recorded scores they see the grade (A/B/C/F), the GPA and the cumulative CGPA. Self-contained
 * postgraduate grading (Policy 16): pass mark 50, no resit.
 */
import { useCallback, useEffect, useState } from "react";
import { reasonHeader } from "@/lib/reason";
import type { Problem } from "@/lib/api";
import { KvGrid, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";

interface Course { id: string; code: string; title: string; units: number; kind: string; semester: number }
interface Entry { entry_id: string; course_id: string; code: string; title: string; units: number; kind: string; ca: number | null; exam: number | null; total: number | null; grade: string | null; points: number | null }
interface Reg { id: string; mode: string; state: string; endorsed_at: string | null }
interface View { programme: string; programmeCode: string; session: string; semester: number; courses: Course[]; registration: Reg | null; entries: Entry[]; gpa: number; cgpa: number }

const KIND: Record<string, string> = { CORE: "Core", ELECTIVE: "Elective", DEFICIENCY: "Deficiency", RESEARCH: "Research" };
const KIND_PILL: Record<string, "info" | "grey" | "ok" | "warn"> = { CORE: "info", ELECTIVE: "grey", RESEARCH: "ok", DEFICIENCY: "warn" };

export function Coursework({ initialSession }: { initialSession: string }) {
  const [session, setSession] = useState(initialSession);
  const [semester, setSemester] = useState(1);
  const [v, setV] = useState<View | null>(null);
  const [picked, setPicked] = useState<Set<string>>(new Set());
  const [mode, setMode] = useState("FULL_TIME");
  const [problem, setProblem] = useState<Problem | null>(null);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);

  const load = useCallback(async (s: string, sem: number) => {
    try {
      const r = await fetch(`/api/bff/api/v1/pg/coursework/me?session=${encodeURIComponent(s)}&semester=${sem}`, { cache: "no-store" });
      setProblem(null);
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); setLoading(false); return; }
      const data = j as View;
      setV(data);
      setPicked(new Set(data.entries.map((e) => e.course_id)));
      if (data.registration?.mode) setMode(data.registration.mode);
    } finally { setLoading(false); }
  }, []);

  useEffect(() => { void load(session, semester); }, [load, session, semester]);

  function toggle(id: string) {
    setPicked((prev) => { const n = new Set(prev); if (n.has(id)) n.delete(id); else n.add(id); return n; });
  }

  async function register() {
    setBusy(true); setProblem(null);
    try {
      const r = await fetch("/api/bff/api/v1/pg/coursework/register", {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Registered ${picked.size} PG courses for ${session} sem ${semester}`) },
        body: JSON.stringify({ session, semester, mode, courseIds: [...picked] }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      const data = j as View;
      setV(data);
      setPicked(new Set(data.entries.map((e) => e.course_id)));
    } finally { setBusy(false); }
  }

  if (loading) return <Note kind="info" title="Loading your courses…">One moment.</Note>;
  if (!v) return <ProblemNotice problem={problem ?? { status: 500, title: "Your coursework could not be read." }} />;

  const pickedUnits = v.courses.filter((c) => picked.has(c.id)).reduce((s, c) => s + c.units, 0);
  const scored = v.entries.filter((e) => e.total != null);
  const endorsed = v.registration?.state === "ENDORSED";
  const unitsSat = scored.reduce((a, e) => a + e.units, 0);
  const unitsPassed = scored.filter((e) => e.grade && e.grade !== "F").reduce((a, e) => a + e.units, 0);
  const cgpa = Number(v.cgpa);

  return (
    <>
      {problem ? <ProblemNotice problem={problem} /> : null}

      <Panel title={v.programme} right={
        <span style={{ display: "flex", gap: 6 }}>
          <input className="ctl tnum" style={{ width: 110 }} value={session} onChange={(e) => setSession(e.target.value)} aria-label="Session" />
          <select className="ctl" style={{ width: "auto" }} value={semester} onChange={(e) => setSemester(Number(e.target.value))} aria-label="Semester">
            <option value={1}>First semester</option><option value={2}>Second semester</option>
          </select>
        </span>
      }>
        <PBody>
          <div className="sub2">
            {v.registration
              ? <>Registered ({KIND[v.registration.mode] ?? v.registration.mode.toLowerCase()}) · {endorsed ? <Pil kind="ok">Endorsed</Pil> : <Pil kind="info">{v.registration.state.toLowerCase()}</Pil>}</>
              : "Not registered for this semester yet."}
          </div>
        </PBody>
      </Panel>

      {scored.length ? (
        <Panel title="Results" right={`GPA ${Number(v.gpa).toFixed(2)} · CGPA ${Number(v.cgpa).toFixed(2)}`}>
          <DTable cols={["Course", "Title", "Units|num", "CA|num", "Exam|num", "Total|num", "Grade|mid", "Points|num"]}
            rows={scored.map((e) => [
              <span key="c" className="tnum">{e.code}</span>, e.title, <span key="u" className="tnum">{e.units}</span>,
              <span key="ca" className="tnum">{e.ca ?? "—"}</span>, <span key="ex" className="tnum">{e.exam ?? "—"}</span>,
              <span key="t" className="tnum">{e.total}</span>,
              <Pil key="g" kind={e.grade === "F" ? "bad" : e.grade === "C" ? "warn" : "ok"}>{e.grade}</Pil>,
              <span key="p" className="tnum">{e.points != null ? (Number(e.points) * e.units).toFixed(0) : "—"}</span>,
            ])} texts={scored.map((e) => `${e.code} ${e.title}`)} />
          <PBody>
            <KvGrid cls="grid--4" pairs={[
              ["GPA (this semester)", Number(v.gpa).toFixed(2)],
              ["CGPA", cgpa.toFixed(2)],
              ["Units passed", `${unitsPassed} of ${unitsSat}`],
              ["Standing", cgpa >= 2.5 ? <Pil kind="ok">Good standing</Pil> : <Pil kind="bad">Probation</Pil>],
            ]} />
            <div className="sub2" style={{ marginTop: 8 }}>Grading (Policy 16): A 70+ · B 60–69 · C 50–59 · F 0–49. Pass mark 50; there is no resit. A CGPA below 2.50 places you on probation for a semester.</div>
          </PBody>
        </Panel>
      ) : null}

      <Panel title="Course registration" right={`${pickedUnits} units selected`}>
        <PBody>
          {endorsed ? (
            <Note kind="ok" title="Your registration is endorsed">The Head of Department has endorsed this semester&rsquo;s registration. Write to the department to change it.</Note>
          ) : v.courses.length ? (
            <>
              <div style={{ display: "grid", gap: 6 }}>
                {v.courses.map((c) => {
                  const on = picked.has(c.id);
                  const locked = v.entries.some((e) => e.course_id === c.id && e.total != null);
                  return (
                    <label key={c.id} style={{ display: "flex", alignItems: "center", gap: 10, padding: "6px 0", borderBottom: "1px solid var(--line-2)", opacity: locked ? 0.7 : 1 }}>
                      <input type="checkbox" className="pchk" checked={on} disabled={locked || busy} onChange={() => toggle(c.id)} />
                      <span className="tnum" style={{ width: 72 }}>{c.code}</span>
                      <span style={{ flexGrow: 1 }}>{c.title}</span>
                      <Pil kind={KIND_PILL[c.kind] ?? "grey"}>{KIND[c.kind] ?? c.kind}</Pil>
                      <span className="tnum sub2" style={{ width: 56, textAlign: "right" }}>{c.units} u</span>
                    </label>
                  );
                })}
              </div>
              <div style={{ display: "flex", gap: 10, alignItems: "center", flexWrap: "wrap", marginTop: 12 }}>
                <select className="ctl" style={{ width: "auto" }} value={mode} onChange={(e) => setMode(e.target.value)} aria-label="Mode">
                  <option value="FULL_TIME">Full-time</option><option value="PART_TIME">Part-time</option>
                </select>
                <button type="button" className="btn btn--primary btn--sm" disabled={busy || picked.size === 0} onClick={() => void register()}>
                  {busy ? "Saving…" : v.registration ? "Update registration" : "Register these courses"}
                </button>
                <span className="sub2">Minimum coursework is 24 units for a taught programme (Policy 15).</span>
              </div>
            </>
          ) : (
            <Note kind="info" title="No courses listed for this semester yet">Your department sets the courses the programme carries. Check back, or ask the department.</Note>
          )}
        </PBody>
      </Panel>
    </>
  );
}
