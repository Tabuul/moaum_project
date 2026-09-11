"use client";

/** Upload a department's course structure from the CCMAS document (or an .xlsx). ICT/Super and the HOD load it;
 *  each course is created and offered to the programme at its level. Level and semester come from the document's
 *  own headings (100 Level / First Semester); nothing is typed. (V084) */
import { useState } from "react";
import { reasonHeader } from "@/lib/reason";
import type { Problem } from "@/lib/api";
import { docxBlocks } from "@/lib/docx";
import { xlsxRows, buildXlsx } from "@/lib/xlsx";
import { Btn, Note, Panel, PBody, Tiles } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

interface ProgrammeOption { code: string; name: string; facultyName?: string }
interface Row { code: string; title: string; units: string; status: string; level: number | null; semester: number | null; lh: string; ph: string }
const MAY = ["ict", "super", "admin", "hod", "dean", "academic", "registrar", "dregistrar"];

export function Courses({ programmes, actingOffice }: { programmes: ProgrammeOption[]; actingOffice: string | null }) {
  const may = MAY.includes(actingOffice ?? "");
  const [programme, setProgramme] = useState("");
  const [session, setSession] = useState("");
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [msg, setMsg] = useState<string | null>(null);
  const [preview, setPreview] = useState<Row[] | null>(null);

  function downloadTemplate() {
    const blob = buildXlsx(
      ["Session", "Course Code", "Course Title", "Units", "Status", "Level", "Semester", "Lecture Hours", "Practical Hours"],
      [
        ["2025/2026", "BSU-SOC-101", "Introduction to Sociology", "3", "C", "100", "1", "45", ""],
        ["2025/2026", "BSU-SOC-102", "Social Institutions", "2", "C", "100", "2", "30", ""],
      ],
      "Course structure",
    );
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = "Course structure template.xlsx";
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  }

  async function rowsFromDocx(buf: ArrayBuffer): Promise<Row[]> {
    const blocks = await docxBlocks(buf);
    const rows: Row[] = [];
    let level: number | null = null;
    let semester: number | null = null;
    for (const b of blocks) {
      if (b.kind === "p") {
        const lm = b.text.match(/(\d{3})\s*level/i);
        if (lm) level = Number(lm[1]);
        if (/first|1st/i.test(b.text) && /semester/i.test(b.text)) semester = 1;
        else if (/second|2nd/i.test(b.text) && /semester/i.test(b.text)) semester = 2;
        else if (/third|3rd/i.test(b.text) && /semester/i.test(b.text)) semester = 3;
        continue;
      }
      for (const r of b.rows) {
        const code = (r[0] ?? "").trim();
        if (!code || /^course\s*code$/i.test(code) || /^total$/i.test((r[1] ?? "").trim())) continue;
        rows.push({ code, title: (r[1] ?? "").trim(), units: (r[2] ?? "").trim(), status: (r[3] ?? "").trim(), level, semester, lh: (r[4] ?? "").trim(), ph: (r[5] ?? "").trim() });
      }
    }
    return rows;
  }

  async function rowsFromXlsx(buf: ArrayBuffer): Promise<{ rows: Row[]; session: string }> {
    const grid = await xlsxRows(buf);
    const header = (grid[0] ?? []).map((c) => String(c ?? "").trim().toLowerCase());
    const at = (names: string[]) => header.findIndex((h) => names.some((n) => h.includes(n)));
    const ci = { code: at(["code"]), title: at(["title", "course"]), units: at(["unit"]), status: at(["status"]), level: at(["level"]), sem: at(["semester", "sem"]), lh: at(["lh", "lecture"]), ph: at(["ph", "practical"]), session: at(["session"]) };
    if (ci.code < 0) return { rows: [], session: "" };
    const body = grid.slice(1).filter((r) => (r[ci.code] ?? "").toString().trim());
    const rows = body.map((r) => {
      const g = (i: number) => (i >= 0 ? String(r[i] ?? "").trim() : "");
      const lv = Number(g(ci.level).replace(/[^0-9]/g, ""));
      const sm = Number(g(ci.sem).replace(/[^0-9]/g, ""));
      return { code: g(ci.code), title: g(ci.title), units: g(ci.units), status: g(ci.status), level: lv || null, semester: sm || null, lh: g(ci.lh), ph: g(ci.ph) };
    }).filter((x) => !/^course\s*code$/i.test(x.code));
    const session = ci.session >= 0 ? (body.map((r) => String(r[ci.session] ?? "").trim()).find((s) => /^[0-9]{4}\/[0-9]{4}$/.test(s)) ?? "") : "";
    return { rows, session };
  }

  async function read(file: File) {
    setBusy(true);
    setProblem(null);
    setMsg(null);
    setPreview(null);
    try {
      const buf = await file.arrayBuffer();
      let rows: Row[];
      if (file.name.toLowerCase().endsWith(".xlsx")) {
        const out = await rowsFromXlsx(buf);
        rows = out.rows;
        if (out.session && !session) setSession(out.session);
      } else {
        rows = await rowsFromDocx(buf);
      }
      if (!rows.length) { setProblem({ status: 400, title: "No courses were found in that file.", detail: "Download the template, or upload the CCMAS .docx (its tables of Course Code, Title, Units, Status) or an .xlsx with those columns." }); return; }
      setPreview(rows);
    } catch {
      setProblem({ status: 400, title: "That file could not be read.", detail: "Upload the department's CCMAS .docx or an .xlsx." });
    } finally {
      setBusy(false);
    }
  }

  async function upload() {
    if (!preview || !programme) return;
    setBusy(true);
    setProblem(null);
    setMsg(null);
    try {
      const r = await fetch("/api/bff/api/v1/catalogue/import", { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Course structure uploaded for ${programme}${session ? ` (${session})` : ""}`) }, body: JSON.stringify({ programme, session: session || null, rows: preview }) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); return; }
      const c = j as { courses: number; offers: number; bad_code: number };
      setMsg(`${c.courses} courses created or updated and offered to the programme${c.bad_code ? ` · ${c.bad_code} rows had a code the catalogue could not accept` : ""}.`);
      setPreview(null);
    } finally {
      setBusy(false);
    }
  }

  const byLevel = preview ? [...new Set(preview.map((r) => r.level))].filter(Boolean).sort() : [];

  return (
    <>
      <Note kind="info" title="Load a department's approved course structure">
        Upload the CCMAS document for a programme. Each course — with its units, status and lecture/practical hours — is
        created in the catalogue and offered to the programme at its level; the level and semester are read from the
        document&rsquo;s own headings. Uploading again updates rather than duplicates. The Directorate of ICT and the
        Super Administrator may load any department&rsquo;s; an HOD loads their own.
      </Note>
      {!may ? <Note kind="bad" title="This desk is for the Directorate of ICT, the Super Administrator and HODs">Your office may not upload a course structure.</Note> : null}

      <Panel title="The programme and its document" right="CCMAS structure">
        <PBody>
          <div className="grid grid--2">
            <Field id="cu-prog" label="Programme" hint="The programme these courses belong to">
              <select id="cu-prog" className="ctl" value={programme} onChange={(e) => setProgramme(e.target.value)}>
                <option value="">Choose the programme…</option>
                {programmes.map((p) => <option key={p.code} value={p.code}>{p.name}{p.facultyName ? ` · ${p.facultyName}` : ""}</option>)}
              </select>
            </Field>
            <Field id="cu-ses" label="Session" hint="The session this structure is for, e.g. 2025/2026 (read from the template's Session column when present)">
              <input id="cu-ses" className="ctl tnum" value={session} placeholder="2025/2026" onChange={(e) => setSession(e.target.value.trim())} />
            </Field>
          </div>
          <div style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" }}>
            <Btn kind="ghost" onClick={downloadTemplate}>Download template</Btn>
            <label className={`btn btn--primary${!may || !programme || busy ? " btn--disabled" : ""}`} style={{ cursor: may && programme && !busy ? "pointer" : "not-allowed", margin: 0, opacity: !may || !programme ? 0.6 : 1 }}>
              {busy ? "Reading…" : "Choose the course document (.docx or .xlsx)"}
              <input type="file" accept=".docx,.xlsx" style={{ display: "none" }} disabled={!may || !programme || busy} onChange={(e) => { const f = e.target.files?.[0]; if (f) void read(f); e.target.value = ""; }} />
            </label>
            {!programme ? <span className="sub2">Choose the programme first.</span> : null}
          </div>
          <div className="sub2" style={{ marginTop: 8 }}>The template carries a <b>Session</b> and a <b>Semester</b> column alongside Level, so each course says which semester it runs — no reliance on the document&rsquo;s headings. Status: C compulsory, R required, E elective, GST. Fill it, or upload the CCMAS .docx as before.</div>
        </PBody>
      </Panel>

      {problem ? <ProblemNotice problem={problem} /> : null}
      {msg ? <Note kind="ok" title="Course structure loaded">{msg}</Note> : null}

      {preview ? (
        <Panel title="Read from the document — check, then load" right={`${preview.length} course${preview.length === 1 ? "" : "s"}${byLevel.length ? ` · levels ${byLevel.join(", ")}` : ""}`}>
          <PBody>
            <Tiles items={[
              ["Courses read", String(preview.length), null, "Ready to load"],
              ["Levels", byLevel.length ? byLevel.join(", ") : "—", null, "From the headings"],
              ["With a code the rule rejects", String(preview.filter((r) => !/^[A-Z][A-Z0-9 /-]{2,19}$/.test(r.code.toUpperCase())).length), null, "Shown, not loaded"],
            ]} />
            <div style={{ maxHeight: 260, overflowY: "auto", border: "1px solid var(--line)", borderRadius: 8 }}>
              <table className="tbl" style={{ width: "100%" }}>
                <thead><tr><th>Code</th><th>Title</th><th>Units</th><th>Status</th><th>Level</th><th>Sem</th></tr></thead>
                <tbody>
                  {preview.slice(0, 200).map((r, i) => (
                    <tr key={i}><td className="tnum">{r.code}</td><td>{r.title}</td><td className="tnum">{r.units}</td><td>{r.status}</td><td className="tnum">{r.level ?? "—"}</td><td className="tnum">{r.semester ?? "—"}</td></tr>
                  ))}
                </tbody>
              </table>
            </div>
            <div style={{ marginTop: 10, display: "flex", gap: 8 }}>
              <button type="button" className="btn btn--primary" disabled={busy || !may} onClick={() => void upload()}>{busy ? "Loading…" : `Load ${preview.length} courses`}</button>
              <button type="button" className="btn btn--ghost" disabled={busy} onClick={() => setPreview(null)}>Cancel</button>
            </div>
          </PBody>
        </Panel>
      ) : null}
    </>
  );
}
