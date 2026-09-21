"use client";

/**
 * The postgraduate course catalogue (V211): the department / School defines the courses each programme
 * carries — a three-letter prefix and a 700/800/900 number, the units, and whether the course is core,
 * elective, deficiency or research (Policy 11). Students register these on their own screen.
 */
import { useCallback, useEffect, useMemo, useState } from "react";
import { reasonHeader } from "@/lib/reason";
import type { Problem } from "@/lib/api";
import { Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";

interface Prog { code: string; name: string; faculty_name: string; department_name: string }
interface Course { id: string; code: string; title: string; units: number; kind: string; semester: number; active: boolean }

const KIND: Record<string, string> = { CORE: "Core", ELECTIVE: "Elective", DEFICIENCY: "Deficiency", RESEARCH: "Research" };
const KIND_PILL: Record<string, "info" | "grey" | "ok" | "warn"> = { CORE: "info", ELECTIVE: "grey", RESEARCH: "ok", DEFICIENCY: "warn" };

export function CoursesDesk({ mayEdit }: { mayEdit: boolean }) {
  const [progs, setProgs] = useState<Prog[]>([]);
  const [programme, setProgramme] = useState("");
  const [courses, setCourses] = useState<Course[]>([]);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [busy, setBusy] = useState(false);
  const [f, setF] = useState({ code: "", title: "", units: "3", kind: "CORE", semester: "1" });

  useEffect(() => {
    let live = true;
    fetch("/api/bff/api/v1/pg/programmes").then((r) => (r.ok ? r.json() : [])).then((j) => { if (live) setProgs(Array.isArray(j) ? j : []); }).catch(() => {});
    return () => { live = false; };
  }, []);

  const loadCourses = useCallback(async (p: string) => {
    if (!p) { await Promise.resolve(); setCourses([]); return; }
    const r = await fetch(`/api/bff/api/v1/pg/coursework/courses?programme=${encodeURIComponent(p)}`, { cache: "no-store" });
    setProblem(null);
    const j = await r.json().catch(() => null);
    if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
    setCourses(Array.isArray(j) ? (j as Course[]) : []);
  }, []);

  useEffect(() => { void (async () => { await loadCourses(programme); })(); }, [programme, loadCourses]);

  const byFaculty = useMemo(() => {
    const m = new Map<string, Prog[]>();
    for (const p of progs) { const k = p.faculty_name; if (!m.has(k)) m.set(k, []); m.get(k)!.push(p); }
    return [...m.entries()];
  }, [progs]);

  async function addCourse() {
    if (!programme || !f.code.trim() || !f.title.trim()) { setProblem({ status: 400, title: "Programme, course code and title are required." }); return; }
    setBusy(true); setProblem(null);
    try {
      const r = await fetch("/api/bff/api/v1/pg/coursework/courses", {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Added PG course ${f.code} to ${programme}`) },
        body: JSON.stringify({ programmeCode: programme, code: f.code.trim(), title: f.title.trim(), units: Number(f.units) || 0, kind: f.kind, semester: Number(f.semester) || 1 }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      setF({ code: "", title: "", units: "3", kind: "CORE", semester: "1" });
      await loadCourses(programme);
    } finally { setBusy(false); }
  }

  const chosen = progs.find((p) => p.code === programme);
  const totalUnits = courses.filter((c) => c.kind !== "DEFICIENCY").reduce((s, c) => s + c.units, 0);

  return (
    <>
      {problem ? <ProblemNotice problem={problem} /> : null}
      <Panel title="Programme" right={chosen ? `${chosen.department_name} · ${chosen.faculty_name}` : "Choose a programme"}>
        <PBody>
          <select className="ctl" value={programme} onChange={(e) => setProgramme(e.target.value)} style={{ maxWidth: 460 }}>
            <option value="">Choose a postgraduate programme…</option>
            {byFaculty.map(([fac, list]) => (
              <optgroup key={fac} label={fac}>
                {list.map((p) => <option key={p.code} value={p.code}>{p.name}</option>)}
              </optgroup>
            ))}
          </select>
        </PBody>
      </Panel>

      {programme ? (
        <Panel title="Courses" right={`${courses.length} course${courses.length === 1 ? "" : "s"} · ${totalUnits} credit units`}>
          {courses.length ? (
            <DTable cols={["Code", "Title", "Units|num", "Type|mid", "Semester|mid", "Status|mid"]}
              rows={courses.map((c) => [
                <span key="c" className="tnum">{c.code}</span>, c.title, <span key="u" className="tnum">{c.units}</span>,
                <Pil key="k" kind={KIND_PILL[c.kind] ?? "grey"}>{KIND[c.kind] ?? c.kind}</Pil>,
                <span key="s" className="sub2">{c.semester === 2 ? "Second" : "First"}</span>,
                c.active ? <Pil key="a" kind="ok">Active</Pil> : <span key="a" className="sub2">Inactive</span>,
              ])} texts={courses.map((c) => `${c.code} ${c.title}`)} />
          ) : <PBody><div className="sub2">No course defined for this programme yet.</div></PBody>}
        </Panel>
      ) : null}

      {programme && mayEdit ? (
        <Panel title="Add a course">
          <PBody>
            <div className="grid grid--2">
              <div className="field"><label htmlFor="c-code">Course code</label><input id="c-code" className="ctl tnum" value={f.code} onChange={(e) => setF({ ...f, code: e.target.value.toUpperCase() })} placeholder="ACC 801" /></div>
              <div className="field"><label htmlFor="c-title">Title</label><input id="c-title" className="ctl" value={f.title} onChange={(e) => setF({ ...f, title: e.target.value })} placeholder="Advanced Financial Accounting" /></div>
              <div className="field"><label htmlFor="c-units">Units</label><input id="c-units" className="ctl tnum" value={f.units} onChange={(e) => setF({ ...f, units: e.target.value.replace(/[^0-9]/g, "") })} /></div>
              <div className="field"><label htmlFor="c-kind">Type</label><select id="c-kind" className="ctl" value={f.kind} onChange={(e) => setF({ ...f, kind: e.target.value })}><option value="CORE">Core</option><option value="ELECTIVE">Elective</option><option value="RESEARCH">Research</option><option value="DEFICIENCY">Deficiency</option></select></div>
              <div className="field"><label htmlFor="c-sem">Semester</label><select id="c-sem" className="ctl" value={f.semester} onChange={(e) => setF({ ...f, semester: e.target.value })}><option value="1">First</option><option value="2">Second</option></select></div>
            </div>
            <div style={{ marginTop: 10 }}><button type="button" className="btn btn--primary btn--sm" disabled={busy} onClick={() => void addCourse()}>{busy ? "Saving…" : "Add course"}</button></div>
            <Note kind="info" title="Course units (Policy 11)">A course unit is one lecture/tutorial hour per week, or three laboratory hours, through a semester. Deficiency courses (max 9 units) earn no credit.</Note>
          </PBody>
        </Panel>
      ) : null}
    </>
  );
}
