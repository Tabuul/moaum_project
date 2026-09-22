"use client";

/**
 * The postgraduate course catalogue (V211): the department / School defines the courses each programme
 * carries — a three-letter prefix and a 700/800/900 number, the units, and whether the course is core,
 * elective, deficiency or research (Policy 11). Students register these on their own screen.
 */
import { useCallback, useEffect, useMemo, useState } from "react";
import { reasonHeader } from "@/lib/reason";
import type { Problem } from "@/lib/api";
import { xlsxRows, csvRows, buildXlsx } from "@/lib/xlsx";
import { Btn, Note, Panel, PBody, Pil } from "@/components/proto/ui";
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
  const [busyUp, setBusyUp] = useState(false);
  const [upResult, setUpResult] = useState<string | null>(null);
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

  function downloadTemplate() {
    const blob = buildXlsx(
      ["Programme", "Course Code", "Title", "Units", "Kind", "Semester"],
      [["M.Sc. Computer Science", "CSC 801", "Advanced Algorithms & Complexity", "3", "Core", "First"]],
      "PG courses",
    );
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = "PG courses template.xlsx";
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  }

  async function uploadCourses(file: File) {
    setBusyUp(true); setProblem(null); setUpResult(null);
    try {
      const isCsv = /\.csv$/i.test(file.name) || file.type === "text/csv";
      const grid = isCsv ? csvRows(await file.text()) : await xlsxRows(await file.arrayBuffer());
      const header = (grid[0] ?? []).map((c) => String(c ?? "").trim().toLowerCase());
      const at = (...re: RegExp[]) => header.findIndex((h) => re.some((rx) => rx.test(h)));
      const col = {
        programme: at(/programme/, /program/, /course of study/), code: at(/course\s*code/, /^code$/, /^course$/),
        title: at(/title/, /^name$/, /descrip/), units: at(/unit/, /credit/, /^cu$/),
        kind: at(/kind/, /type/, /category/), semester: at(/semester/, /^sem$/),
      };
      if (col.programme < 0 || col.code < 0 || col.title < 0) {
        setProblem({ status: 400, title: "The file needs Programme, Course Code and Title columns.", detail: "Download the template to see the exact columns." });
        return;
      }
      const rows: Record<string, string>[] = [];
      for (const r of grid.slice(1)) {
        const g = (i: number) => (i >= 0 ? String(r[i] ?? "").trim() : "");
        const o = { programme: g(col.programme), code: g(col.code), title: g(col.title), units: g(col.units), kind: g(col.kind), semester: g(col.semester) };
        if (o.programme && o.code && o.title) rows.push(o);
      }
      if (!rows.length) { setProblem({ status: 400, title: "No course rows to read.", detail: "Fill the template (delete the example row) and upload it." }); return; }
      const res = await fetch("/api/bff/api/v1/pg/coursework/courses/import", {
        method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`PG course catalogue uploaded: ${rows.length} rows`) },
        body: JSON.stringify({ rows }),
      });
      const j = await res.json().catch(() => null);
      if (!res.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: res.status, title: res.statusText }); return; }
      const c = j as { rows: number; created: number; updated: number; no_programme: number; skipped: number };
      setUpResult(`${c.created} course${c.created === 1 ? "" : "s"} added, ${c.updated} updated${c.no_programme ? ` · ${c.no_programme} row${c.no_programme === 1 ? "" : "s"} had a programme that did not match one on record` : ""}${c.skipped ? ` · ${c.skipped} skipped` : ""}.`);
      if (programme) await loadCourses(programme);
    } catch {
      setProblem({ status: 400, title: "That file could not be read as a spreadsheet.", detail: "Upload the .xlsx built from the template." });
    } finally { setBusyUp(false); }
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

      {mayEdit ? (
        <Panel title="Upload the course catalogue" right="Every programme, from one spreadsheet">
          <PBody>
            <div className="sub2" style={{ marginBottom: 8 }}>
              Bulk-load courses for any postgraduate programme. Columns: <b>Programme</b> (its name or old-portal code), <b>Course Code</b>, <b>Title</b>, <b>Units</b> (0&ndash;12), <b>Kind</b> (Core / Elective / Deficiency / Research) and <b>Semester</b> (First / Second). Column names are matched flexibly. It upserts on programme + code, so re-uploading updates rather than duplicates.
            </div>
            <div style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" }}>
              <Btn kind="ghost" onClick={downloadTemplate}>Download template</Btn>
              <label className={`btn btn--primary btn--sm${busyUp ? " btn--disabled" : ""}`} style={{ cursor: busyUp ? "not-allowed" : "pointer", margin: 0 }}>
                {busyUp ? "Uploading…" : "Upload courses (.xlsx / .csv)"}
                <input type="file" accept=".xlsx,.csv" style={{ display: "none" }} disabled={busyUp} onChange={(e) => { const file = e.target.files?.[0]; if (file) void uploadCourses(file); e.target.value = ""; }} />
              </label>
            </div>
            {upResult ? <div style={{ marginTop: 10 }}><Note kind="ok" title="Course catalogue uploaded">{upResult}</Note></div> : null}
          </PBody>
        </Panel>
      ) : null}

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
