"use client";

/** Migrate students, course registration and past results from the old portal (V082). Each upload reads the
 *  spreadsheet's own columns (matriculation number, course code, marks…) and matches on them; nothing is typed. */
import { useState } from "react";
import { reasonHeader } from "@/lib/reason";
import type { Problem } from "@/lib/api";
import { xlsxRows, buildXlsx } from "@/lib/xlsx";
import { Btn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

type Tab = "students" | "registration" | "results";
const MIGRATE = ["exams", "facultyexams", "hod", "dean", "records", "academic", "registrar", "dregistrar", "super"];

export function Migration({ actingOffice }: { actingOffice: string | null }) {
  const may = MIGRATE.includes(actingOffice ?? "");
  const [tab, setTab] = useState<Tab>("students");
  const [session, setSession] = useState("");
  const [semester, setSemester] = useState("1");
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [result, setResult] = useState<{ tab: Tab; counts: Record<string, number> } | null>(null);

  async function upload(kind: Tab, file: File) {
    setBusy(true);
    setProblem(null);
    setResult(null);
    try {
      const grid = await xlsxRows(await file.arrayBuffer());
      const header = (grid[0] ?? []).map((c) => String(c ?? "").trim());
      if (!header.some((h) => /matric|reg/i.test(h))) {
        setProblem({ status: 400, title: "That file has no matriculation-number column.", detail: "The first row must name the columns; a matriculation (or registration) number is required." });
        return;
      }
      const rows = grid.slice(1)
        .filter((r) => r.some((c) => String(c ?? "").trim() !== ""))
        .map((r) => canonicalRow(kind, header, r))
        .filter((o) => o.matric && !/^matric/i.test(o.matric));
      if (!rows.length) { setProblem({ status: 400, title: "The file had no rows to read.", detail: "Export the list from the old portal and upload it." }); return; }
      const path = kind === "students" ? "/api/bff/api/v1/results/legacy/students"
        : kind === "registration" ? "/api/bff/api/v1/results/legacy/registration" : "/api/bff/api/v1/results/legacy/results";
      const body = kind === "students" ? { rows } : { session, semester: Number(semester), rows };
      const r = await fetch(path, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Legacy ${kind} imported${kind === "students" ? "" : ` for ${session} semester ${semester}`}`) }, body: JSON.stringify(body) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); return; }
      setResult({ tab: kind, counts: j as Record<string, number> });
    } catch {
      setProblem({ status: 400, title: "That file could not be read as a spreadsheet.", detail: "Upload the .xlsx exported from the old portal." });
    } finally {
      setBusy(false);
    }
  }

  /* the download templates — the columns each import reads, with one example row to delete */
  const TEMPLATES: Record<Tab, { name: string; headers: string[]; example: string[] }> = {
    students: {
      name: "Students biodata",
      headers: ["Matriculation Number", "Surname", "Other Names", "Programme", "Sex", "Date of Birth", "Entry Mode", "Entry Session", "Level"],
      example: ["MOAUM/CSC/22/0001", "Doe", "John Ada (example — delete this row)", "Computer Science", "M", "2003-05-14", "UTME", "2022/2023", "300"],
    },
    registration: {
      name: "Course registration",
      headers: ["Matriculation Number", "Course Code", "Course Title", "Units", "Level"],
      example: ["MOAUM/CSC/22/0001", "CSC 301", "Operating Systems (example — delete this row)", "3", "300"],
    },
    results: {
      name: "Past results",
      headers: ["Matriculation Number", "Course Code", "Course Title", "Units", "Level", "CA", "Exam", "Total", "Outcome"],
      example: ["MOAUM/CSC/22/0001", "CSC 301", "Operating Systems (example — delete this row)", "3", "300", "25", "55", "80", "GRADED"],
    },
  };

  function downloadTemplate(kind: Tab) {
    const t = TEMPLATES[kind];
    const blob = buildXlsx(t.headers, [t.example], t.name);
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = `${t.name} template.xlsx`;
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  }

  const needScope = tab !== "students";
  const scopeReady = !needScope || (/^[0-9]{4}\/[0-9]{4}$/.test(session) && ["1", "2", "3"].includes(semester));
  const CARDS: Record<Tab, [string, string][]> = {
    students: [["rows", "Rows read"], ["created", "New students"], ["updated", "Updated"], ["no_programme", "Programme not found"], ["bad_number", "Bad matric format"]],
    registration: [["rows", "Rows read"], ["students", "Students"], ["offerings", "Courses"], ["registrations", "Registrations"], ["no_student", "No such student"], ["no_course", "No such course"]],
    results: [["rows", "Rows read"], ["students", "Students"], ["results", "Results posted"], ["registrations", "Registrations made"], ["no_student", "No such student"], ["no_course", "No such course"], ["no_mark", "No / invalid mark"]],
  };

  /* map an old-portal export's own column names onto the keys the importer reads, so a real file
     uploads without renaming — CA in [0,40], Exam in [0,60], Total in [0,100]; an out-of-range
     mark is skipped and reported, not fatal. */
  function canonicalRow(kind: Tab, header: string[], r: (string | number | null)[]): Record<string, string> {
    const h = header.map((x) => String(x ?? "").trim().toLowerCase());
    const val = (i: number) => (i >= 0 ? String(r[i] ?? "").trim() : "");
    const at = (...names: RegExp[]) => h.findIndex((x) => names.some((n) => n.test(x)));
    const o: Record<string, string> = {};
    const put = (key: string, i: number) => { if (i >= 0 && val(i)) o[key] = val(i); };
    put("matric", at(/matric/, /reg\.?\s*(no|number)/, /registration/));
    if (kind === "students") {
      put("surname", at(/surname/, /last\s*name/));
      put("otherNames", at(/other\s*name/, /first\s*name/, /given/));
      put("name", at(/full\s*name/, /^name$/, /student\s*name/, /^names$/));
      put("programme", at(/programme/, /program/, /course of study/, /department|dept/));
      put("sex", at(/^sex$/, /gender/));
      put("dob", at(/birth/, /^dob$/, /d\.o\.b/));
      put("entryMode", at(/entry\s*mode/, /mode of entry/, /^mode$/, /admission type/));
      put("entrySession", at(/entry\s*session/, /admission\s*session/, /year of entry/, /session admitted/));
      put("level", at(/current\s*level/, /^level$/, /^lvl$/));
    } else {
      put("course", at(/course\s*code/, /^course$/, /^code$/, /subject\s*code/));
      put("units", at(/unit/, /^cu$/, /credit/));
      put("level", at(/^level$/, /^lvl$/));
      if (kind === "results") {
        put("ca", at(/\bca\b/, /continuous/, /c\.a/));
        put("exam", at(/exam/, /examination/));
        put("total", at(/total/, /^score$/, /^mark$/, /aggregate/));
        put("outcome", at(/outcome/, /remark/, /status/, /grade/));
      }
    }
    return o;
  }

  return (
    <>
      <Note kind="info" title="Bring the record over from the old portal, in three steps">
        Migrate the students first (so results and registration can match them by matriculation number), then the
        course registration and the past results. Each upload reads the spreadsheet&rsquo;s own columns and matches on
        the matriculation number and the course code &mdash; nothing is typed. A past result is imported as final under
        a legacy minute, so it counts on the transcript and the GPA exactly as one entered here. Every import is your act.
      </Note>
      {!may ? <Note kind="bad" title="This desk is for the Examinations Officer, HODs and Records">Your office may not migrate records.</Note> : null}

      <div className="card"><div className="card__body">
        <div className="role-tabs" role="tablist">
          {([["students", "1 · Students biodata"], ["registration", "2 · Course registration"], ["results", "3 · Past results"]] as [Tab, string][]).map(([k, l]) => (
            <button key={k} type="button" role="tab" aria-selected={tab === k ? "true" : "false"} onClick={() => { setTab(k); setResult(null); setProblem(null); }}>{l}</button>
          ))}
        </div>
      </div></div>

      {problem ? <ProblemNotice problem={problem} /> : null}

      <Panel title={tab === "students" ? "Students exported from the old portal" : tab === "registration" ? "Course registration of a past semester" : "Past results of a semester"}
             right={tab === "students" ? "The first step" : `${session || "session"} · semester ${semester}`}>
        <PBody>
          {needScope ? (
            <div className="grid grid--3">
              <Field id="mg-ses" label="Session" hint="The session these records belong to, e.g. 2024/2025"><input id="mg-ses" className="ctl tnum" value={session} placeholder="2024/2025" onChange={(e) => setSession(e.target.value.trim())} /></Field>
              <Field id="mg-sem" label="Semester"><select id="mg-sem" className="ctl" value={semester} onChange={(e) => setSemester(e.target.value)}><option value="1">First semester</option><option value="2">Second semester</option><option value="3">Third semester</option></select></Field>
              <div />
            </div>
          ) : null}
          <div className="sub2" style={{ marginBottom: 8 }}>
            {tab === "students" ? "Columns read: matriculation number, name (or surname + other names), programme (code or name), sex, date of birth, entry mode, level. The session is read from the matric number when not given."
              : tab === "registration" ? "Columns read: matriculation number, course code, units. Each student's approved registration and course entries are created for the semester above."
              : "Columns read: matriculation number, course code, and the mark. Fill CA and Exam where the old record splits them (they add to the total); otherwise leave those blank and fill Total (0–100). Units and outcome are read when present."}
          </div>
          <div style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" }}>
            <Btn kind="ghost" onClick={() => downloadTemplate(tab)}>Download template</Btn>
            <label className={`btn btn--primary${!may || (needScope && !scopeReady) || busy ? " btn--disabled" : ""}`} style={{ cursor: may && scopeReady && !busy ? "pointer" : "not-allowed", margin: 0, opacity: !may || (needScope && !scopeReady) ? 0.6 : 1 }}>
              {busy ? "Importing…" : `Upload ${tab === "students" ? "students" : tab === "registration" ? "registration" : "results"} file`}
              <input type="file" accept=".xlsx" style={{ display: "none" }} disabled={!may || (needScope && !scopeReady) || busy} onChange={(e) => { const f = e.target.files?.[0]; if (f) void upload(tab, f); e.target.value = ""; }} />
            </label>
            {needScope && !scopeReady ? <span className="sub2">Enter the session (YYYY/YYYY) and semester first.</span> : null}
          </div>
          <div className="sub2" style={{ marginTop: 8 }}>Download the template, fill it from the old-portal export (delete the example row), and upload it. Column names are matched flexibly, so an export that already has these columns can be uploaded as-is.</div>
        </PBody>
      </Panel>

      {result && result.tab === tab ? (
        <>
          <Tiles items={CARDS[tab].map(([k, label]) => {
            const v = Number(result.counts[k] ?? 0);
            const bad = /no_|bad_/.test(k) && v > 0;
            return [label, String(v), bad ? "var(--red-ink)" : /created|results|registrations|students/.test(k) ? "var(--green-ink)" : null, ""] as [string, string, string | null, string];
          })} />
          <Note kind="ok" title="Imported">
            {tab === "students" ? `${result.counts.created ?? 0} students created, ${result.counts.updated ?? 0} updated.`
              : tab === "registration" ? `${result.counts.registrations ?? 0} registrations across ${result.counts.offerings ?? 0} courses.`
              : `${result.counts.results ?? 0} results posted.`}
            {" "}Rows that did not match are counted above; fix them at source and re-upload — the import is idempotent.
            {(result.counts.no_student ?? 0) > 0 ? <> <b>Import the students first</b> if a number was not found.</> : null}
          </Note>
        </>
      ) : null}

      <Note kind="info" title="Order matters, and re-uploading is safe">
        <Pil kind="grey">1</Pil> Students &rarr; <Pil kind="grey">2</Pil> Registration &rarr; <Pil kind="grey">3</Pil> Results.
        A result needs the student and the course registration to exist, so the results import also creates the
        registration entry if it is missing. Uploading the same file again updates rather than duplicates.
      </Note>
    </>
  );
}
