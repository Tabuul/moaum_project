"use client";

/** t/departmentupload — create a department, or upload a list of them (V118). ICT/Academic and structure offices. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify , notifyProblem } from "@/components/proto/Toast";
import { xlsxRows, csvRows, buildXlsx } from "@/lib/xlsx";
import { brandedXlsx, brandedPrint, downloadBlob, docSerial } from "@/lib/exportbrand";
import { Btn, IcoBtn, Note, Panel, PBody, RoleLine, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface Department { code: string; name: string; faculty_code: string; faculty_name: string; programmes: number; courses: number }
const MAY = ["ict", "super", "admin", "academic", "registrar", "dregistrar"];

export function Departments({ departments, actingOffice }: { departments: Department[]; actingOffice: string | null }) {
  const router = useRouter();
  const may = MAY.includes(actingOffice ?? "");
  const [code, setCode] = useState("");
  const [name, setName] = useState("");
  const [faculty, setFaculty] = useState("");
  const [editing, setEditing] = useState(false);
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [msg, setMsg] = useState<string | null>(null);

  function downloadTemplate() {
    const blob = buildXlsx(["Code", "Name", "Faculty"], [["MTC", "Mathematics and Computer Science (example — delete this row)", "SC"]], "Departments");
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = "Departments template.xlsx";
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  }

  async function post(path: string, body: unknown, reason: string): Promise<Record<string, unknown> | null> {
    setBusy(true); setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/catalogue${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); notifyProblem(j ?? { status: r.status, title: r.statusText }); return null; }
      notify(reason);
      router.refresh();
      return j;
    } finally { setBusy(false); }
  }

  async function remove(d: Department) {
    if (d.programmes || d.courses) { setProblem({ status: 400, title: `${d.name} still has ${d.programmes} programme(s) and ${d.courses} course(s).`, detail: "Remove or move them first; a department is deleted only when it is empty." }); notifyProblem({ status: 400, title: `${d.name} still has ${d.programmes} programme(s) and ${d.courses} course(s).`, detail: "Remove or move them first; a department is deleted only when it is empty." }); return; }
    if (!window.confirm(`Remove ${d.name}? This cannot be undone.`)) return;
    setBusy(true); setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/catalogue/departments/${encodeURIComponent(d.code)}`, { method: "DELETE", headers: { "X-Reason": reasonHeader(`Department ${d.code} removed`) } });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
      setMsg(`Department ${d.code} removed.`); notify(`Department ${d.code} removed`); router.refresh();
    } finally { setBusy(false); }
  }

  const EXPORT_COLS = ["Code", "Name", "Faculty", "Programmes", "Courses"];
  const exportRows = () => departments.map((d) => [d.code, d.name, d.faculty_name, d.programmes, d.courses]);
  async function exportXlsx() {
    downloadBlob(await brandedXlsx("Departments on the register", EXPORT_COLS, exportRows(), { serial: docSerial("DEP") }), "Departments.xlsx");
  }
  function exportPdf() {
    brandedPrint("Departments on the register", `${departments.length} departments`, EXPORT_COLS, exportRows(), docSerial("DEP"));
  }

  async function upload(file: File) {
    setMsg(null); setProblem(null);
    try {
      let grid: (string | number | null)[][];
      try {
        grid = /\.csv$/i.test(file.name) || file.type === "text/csv" ? csvRows(await file.text()) : await xlsxRows(await file.arrayBuffer());
      } catch (err) {
        setProblem({ status: 400, title: "That file could not be read.", detail: `${err instanceof Error ? err.message : String(err)}. Save it from Excel as “Excel Workbook (.xlsx)” or “CSV (Comma delimited) (.csv)” and upload that.` }); notifyProblem({ status: 400, title: "That file could not be read.", detail: `${err instanceof Error ? err.message : String(err)}. Save it from Excel as “Excel Workbook (.xlsx)” or “CSV (Comma delimited) (.csv)” and upload that.` });
        return;
      }
      const header = (grid[0] ?? []).map((c) => String(c ?? "").trim().toLowerCase());
      const at = (n: string[]) => header.findIndex((h) => n.some((x) => h.includes(x)));
      const ci = { code: at(["code"]), name: at(["name", "department", "dept"]), faculty: at(["faculty"]) };
      if (ci.code < 0 || ci.name < 0 || ci.faculty < 0) { setProblem({ status: 400, title: "That file needs Code, Name and Faculty columns.", detail: "Download the template." }); notifyProblem({ status: 400, title: "That file needs Code, Name and Faculty columns.", detail: "Download the template." }); return; }
      const g = (r: (string | number | null)[], i: number) => (i >= 0 ? String(r[i] ?? "").trim() : "");
      const rows = grid.slice(1).filter((r) => g(r, ci.code) && !/^code$/i.test(g(r, ci.code))).map((r) => ({
        code: g(r, ci.code), name: g(r, ci.name), faculty: g(r, ci.faculty),
      }));
      if (!rows.length) { setProblem({ status: 400, title: "No departments found in the file." }); notifyProblem({ status: 400, title: "No departments found in the file." }); return; }
      const j = await post("/departments/import", { rows }, `${rows.length} departments uploaded`);
      if (j) { setMsg(`${j.saved ?? 0} departments saved${(j.bad_code ?? 0) ? ` · ${j.bad_code} rows had no name` : ""}${(j.no_faculty ?? 0) ? ` · ${j.no_faculty} with no matching faculty` : ""}.`); notify(`${j.saved ?? 0} departments saved`); }
    } catch { setProblem({ status: 400, title: "That file could not be read as a spreadsheet." }); notifyProblem({ status: 400, title: "That file could not be read as a spreadsheet." }); }
  }

  return (
    <>
      <RoleLine allowed={["academic", "registrar", "dregistrar"]} actingOffice={actingOffice} canAct={may} action="Creating and editing departments" />
      <Note kind="info" title="Create a department, or upload the list">
        A department carries a code, a name and a faculty. Create one below, or upload a spreadsheet of them. The faculty
        is matched by code or name and must exist first (add it on the Faculty upload screen). Uploading again updates
        rather than duplicates; programmes and courses hang off the department.
      </Note>
      {!may ? <Note kind="bad" title="This desk is for the Directorate of ICT and the Academic Office">Your office may not manage departments.</Note> : null}
      {problem ? <ProblemNotice problem={problem} /> : null}
      {msg ? <Note kind="ok" title="Departments loaded">{msg}</Note> : null}

      <Tiles items={[["Departments", String(departments.length), null, "On the register"]]} cls="grid--4" />

      {may ? (
        <Panel title={editing ? `Edit ${code}` : "Add a department"} right="Or upload the list">
          <PBody>
            <div className="grid grid--3">
              <Field id="dp-code" label="Code" hint={editing ? "The code cannot change" : "Short, e.g. MTC"}><input id="dp-code" className="ctl tnum" value={code} disabled={editing} onChange={(e) => setCode(e.target.value.toUpperCase())} /></Field>
              <Field id="dp-name" label="Name"><input id="dp-name" className="ctl" value={name} onChange={(e) => setName(e.target.value)} placeholder="Mathematics and Computer Science" /></Field>
              <Field id="dp-fac" label="Faculty" hint="Code or name"><input id="dp-fac" className="ctl" value={faculty} onChange={(e) => setFaculty(e.target.value)} placeholder="SC" /></Field>
            </div>
            <div className="row">
              <Btn kind="primary" disabled={busy || !code.trim() || !name.trim() || !faculty.trim()} onClick={async () => { const j = await post("/departments", { code: code.trim(), name: name.trim(), faculty: faculty.trim() }, `Department ${code.trim()} ${editing ? "edited" : "created"}`); if (j) { setMsg(`Department ${j.code} saved.`); setCode(""); setName(""); setFaculty(""); setEditing(false); } }}>{editing ? "Save changes" : "Save the department"}</Btn>
              {editing ? <Btn kind="ghost" onClick={() => { setCode(""); setName(""); setFaculty(""); setEditing(false); }}>Cancel</Btn> : null}
              <Btn kind="ghost" onClick={downloadTemplate}>Download template</Btn>
              <label className={`btn btn--ghost btn--sm m-0${busy ? " btn--disabled" : ""}`} style={{ cursor: busy ? "not-allowed" : "pointer" }}>
                Upload departments (.xlsx / .csv)
                <input type="file" accept=".xlsx,.csv" style={{ display: "none" }} disabled={busy} onChange={(e) => { const f = e.target.files?.[0]; if (f) void upload(f); e.target.value = ""; }} />
              </label>
            </div>
          </PBody>
        </Panel>
      ) : null}

      <Panel title="Departments" right={<span className="row">
        <span className="sub2">{departments.length} on the register</span>
        <Btn kind="ghost" disabled={!departments.length} onClick={() => void exportXlsx()}>Download Excel</Btn>
        <Btn kind="ghost" disabled={!departments.length} onClick={exportPdf}>Download PDF</Btn>
      </span>}>
        {departments.length ? (
          <DTable cols={["Code|mid", "Name", "Faculty", "Programmes|num", "Courses|num", "|num"]} rows={departments.map((d) => [
            <span className="tnum" key="c">{d.code}</span>, <strong key="n">{d.name}</strong>, <span key="f">{d.faculty_name}</span>,
            <span className="tnum" key="p">{d.programmes}</span>, <span className="tnum" key="k">{d.courses}</span>,
            may ? <span key="x" className="row row--tight row--right">
              <IcoBtn key="e" icon="edit" label={`Edit ${d.name}`} disabled={busy} onClick={() => { setCode(d.code); setName(d.name); setFaculty(d.faculty_code); setEditing(true); if (typeof window !== "undefined") window.scrollTo({ top: 0, behavior: "smooth" }); }} />
              <IcoBtn key="x" icon="trash" danger label={d.programmes || d.courses ? "Empty the department first" : `Remove ${d.name}`} disabled={busy || !!d.programmes || !!d.courses} onClick={() => void remove(d)} />
            </span> : <span className="sub2" key="x">—</span>,
          ])} texts={departments.map((d) => `${d.code} ${d.name} ${d.faculty_name}`)} />
        ) : <PBody><div className="sub2">No department yet. Add one above.</div></PBody>}
      </Panel>
    </>
  );
}
