"use client";
import { notifyProblem } from "@/components/proto/Toast";

/**
 * The postgraduate student's results by semester (V211; V389). Results come from both sources: the School's earlier
 * coursework and the published results of its classes on the University's results chain. Course registration itself is
 * on Course Registration, on the University's registration engine, since V389; a registration made earlier on the
 * School's own list is shown here as it stands. Grading (Policy 16): A 70, B 60, C 50, F below 50; a deficiency course
 * earns no credit.
 */
import { useCallback, useEffect, useState } from "react";
import type { Problem } from "@/lib/api";
import { KvGrid, LinkBtn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";

interface Entry { entry_id: string; course_id: string; code: string; title: string; units: number; kind: string; ca: number | null; exam: number | null; total: number | null; grade: string | null; points: number | null }
interface Reg { id: string; mode: string; state: string; endorsed_at: string | null }
interface Result { code: string; title: string; units: number; kind: string; grade: string | null; points: number | null; total: number | null; source: string }
interface EngineReg { id: string; status: string; courses: number; units: number }
interface View { programme: string; programmeCode: string; session: string; semester: number; registration: Reg | null; entries: Entry[]; gpa: number; cgpa: number;
  results?: Result[]; engineRegistration?: EngineReg | null }

const KIND: Record<string, string> = { CORE: "Core", ELECTIVE: "Elective", DEFICIENCY: "Deficiency", RESEARCH: "Research" };
const KIND_PILL: Record<string, "info" | "grey" | "ok" | "warn"> = { CORE: "info", ELECTIVE: "grey", RESEARCH: "ok", DEFICIENCY: "warn" };
const ENGINE_STATE: Record<string, ["ok" | "info" | "warn" | "grey", string]> = {
  DRAFT: ["grey", "Draft"], SUBMITTED: ["info", "Submitted, awaiting approval"], RETURNED: ["warn", "Returned for correction"], APPROVED: ["ok", "Approved"], LOCKED: ["ok", "Approved"],
};

export function Coursework({ initialSession }: { initialSession: string }) {
  const [session, setSession] = useState(initialSession);
  const [semester, setSemester] = useState(1);
  const [v, setV] = useState<View | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async (s: string, sem: number) => {
    try {
      const r = await fetch(`/api/bff/api/v1/pg/coursework/me?session=${encodeURIComponent(s)}&semester=${sem}`, { cache: "no-store" });
      setProblem(null);
      const j = await r.json().catch(() => null);
      if (!r.ok) { const p = j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }; setProblem(p); notifyProblem(p); setLoading(false); return; }
      setV(j as View);
    } finally { setLoading(false); }
  }, []);

  useEffect(() => { void load(session, semester); }, [load, session, semester]);

  if (loading) return <Note kind="info" title="Loading your courses…">One moment.</Note>;
  if (!v) return <ProblemNotice problem={problem ?? { status: 500, title: "Your coursework could not be read." }} />;

  const results = v.results ?? [];
  const credited = results.filter((e) => e.kind !== "DEFICIENCY" && e.points != null);
  const unitsSat = credited.reduce((a, e) => a + Number(e.units), 0);
  const unitsPassed = credited.filter((e) => e.grade && e.grade !== "F").reduce((a, e) => a + Number(e.units), 0);
  const cgpa = Number(v.cgpa);
  const er = v.engineRegistration ?? null;
  const [erKind, erWord]: ["ok" | "info" | "warn" | "grey", string] = er ? ENGINE_STATE[er.status] ?? ["grey", er.status] : ["grey", ""];

  return (
    <>
      {problem ? <ProblemNotice problem={problem} /> : null}

      <Panel title={v.programme} right={
        <span className="row row--tight">
          <input className="ctl tnum" style={{ width: 110 }} value={session} onChange={(e) => setSession(e.target.value)} aria-label="Session" />
          <select className="ctl" style={{ width: "auto" }} value={semester} onChange={(e) => setSemester(Number(e.target.value))} aria-label="Semester">
            <option value={1}>First semester</option><option value={2}>Second semester</option><option value={3}>Third semester</option>
          </select>
        </span>
      }>
        <PBody>
          {er ? (
            <div className="row row--inline row--tight"><Pil kind={erKind}>{erWord}</Pil><span className="sub2">{er.courses} course(s), {er.units} units on Course Registration</span>
              <LinkBtn kind="ghost" href="/student/register">Course Registration</LinkBtn></div>
          ) : v.registration ? (
            <div className="sub2">Registered on the School&rsquo;s earlier course list · {v.registration.state === "ENDORSED" ? <Pil kind="ok">Endorsed</Pil> : <Pil kind="info">{v.registration.state.toLowerCase()}</Pil>}</div>
          ) : (
            <Note kind="info" title="Not registered for this semester" action={<LinkBtn kind="primary" href="/student/register">Course Registration</LinkBtn>}>
              Postgraduate course registration is on Course Registration, on the School&rsquo;s classes for its session.
            </Note>
          )}
        </PBody>
      </Panel>

      {results.length ? (
        <Panel title="Results" right={`GPA ${Number(v.gpa).toFixed(2)} · CGPA ${cgpa.toFixed(2)}`}>
          <DTable cols={["Course", "Title", "Type|mid", "Units|num", "Total|num", "Grade|mid", "Quality points|num"]}
            rows={results.map((e) => [
              <span key="c" className="tnum">{e.code}</span>, e.title, <Pil key="k" kind={KIND_PILL[e.kind] ?? "grey"}>{KIND[e.kind] ?? e.kind}</Pil>,
              <span key="u" className="tnum">{e.units}</span>, <span key="t" className="tnum">{e.total ?? "—"}</span>,
              e.grade ? <Pil key="g" kind={e.grade === "F" ? "bad" : e.grade === "C" ? "warn" : "ok"}>{e.grade}</Pil> : <span key="g" className="sub2">—</span>,
              <span key="p" className="tnum">{e.points != null && e.kind !== "DEFICIENCY" ? (Number(e.points) * Number(e.units)).toFixed(0) : "—"}</span>,
            ])} texts={results.map((e) => `${e.code} ${e.title}`)} />
          <PBody>
            <KvGrid cls="grid--4" pairs={[
              ["GPA (this semester)", Number(v.gpa).toFixed(2)],
              ["CGPA", cgpa.toFixed(2)],
              ["Units passed", `${unitsPassed} of ${unitsSat}`],
              ["Standing", cgpa >= 2.5 ? <Pil kind="ok">Good standing</Pil> : <Pil kind="bad">Probation</Pil>],
            ]} />
            <div className="sub2 mt-2">A 70+ · B 60–69 · C 50–59 · F 0–49. A deficiency course earns no credit. Results appear once published.</div>
          </PBody>
        </Panel>
      ) : <Panel title="Results"><PBody><div className="sub2">No result is published for this semester yet.</div></PBody></Panel>}

      {v.registration && v.entries.length ? (
        <Panel title="Registered on the School&rsquo;s earlier course list">
          <DTable cols={["Course", "Title", "Type|mid", "Units|num"]} rows={v.entries.map((e) => [
            <span key="c" className="tnum">{e.code}</span>, e.title, <Pil key="k" kind={KIND_PILL[e.kind] ?? "grey"}>{KIND[e.kind] ?? e.kind}</Pil>, <span key="u" className="tnum">{e.units}</span>,
          ])} texts={v.entries.map((e) => `${e.code} ${e.title}`)} />
        </Panel>
      ) : null}
    </>
  );
}
