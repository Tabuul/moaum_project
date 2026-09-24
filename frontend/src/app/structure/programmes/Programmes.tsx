"use client";

/** t/programmeupload — create a programme, or upload a list (V091). ICT/Academic and structure offices.
 *  A programme carries a code (C#####), a name, a faculty, an optional department, category and minimum score. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";
import { xlsxRows, buildXlsx } from "@/lib/xlsx";
import { brandedXlsx, brandedPrint, downloadBlob, docSerial } from "@/lib/exportbrand";
import { Btn, IcoBtn, Note, Panel, PBody, Pil, RoleLine, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface Programme { code: string; name: string; faculty_code: string; faculty_name: string; dept_code: string | null; department_name: string | null; category: string; min_score: number; archived: boolean }
export interface FacultyOption { code: string; name: string }
const MAY = ["ict", "super", "admin", "academic", "registrar", "dregistrar"];

export function Programmes({ programmes, faculties, actingOffice }: { programmes: Programme[]; faculties: FacultyOption[]; actingOffice: string | null }) {
  const router = useRouter();
  const may = MAY.includes(actingOffice ?? "");
  const [f, setF] = useState({ code: "", name: "", faculty: "", deptCode: "", department: "", category: "UNDER GRADUATE", minScore: "" });
  const [editing, setEditing] = useState(false);
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [msg, setMsg] = useState<string | null>(null);

  function downloadTemplate() {
    const blob = buildXlsx(
      ["Code", "Name", "Faculty", "Department Code", "Department", "Category", "Minimum Score"],
      [["C00101", "B.Sc. Computer Science (example — delete this row)", "SCI", "CSC", "Computer Science", "UNDER GRADUATE", "180"]],
      "Programmes");
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = "Programmes template.xlsx";
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  }

  async function post(path: string, body: unknown, reason: string): Promise<Record<string, unknown> | null> {
    setBusy(true); setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/catalogue${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); return null; }
      notify(reason);
      router.refresh();
      return j;
    } finally { setBusy(false); }
  }

  async function archive(p: Programme, archived: boolean) {
    const j = await post(`/programmes/${encodeURIComponent(p.code)}/archive`, { archived }, `Programme ${p.code} ${archived ? "archived" : "restored"}`);
    if (j) setMsg(`${p.name} ${archived ? "archived" : "restored"}.`);
  }

  async function remove(p: Programme) {
    if (!window.confirm(`Delete ${p.name} (${p.code})? This cannot be undone. If any records hang on it, archive it instead.`)) return;
    setBusy(true); setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/catalogue/programmes/${encodeURIComponent(p.code)}`, { method: "DELETE", headers: { "X-Reason": reasonHeader(`Programme ${p.code} removed`) } });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); return; }
      setMsg(`Programme ${p.code} removed.`); notify(`Programme ${p.code} removed`); router.refresh();
    } finally { setBusy(false); }
  }

  function edit(p: Programme) {
    setF({ code: p.code, name: p.name, faculty: p.faculty_code, deptCode: p.dept_code ?? "", department: p.department_name ?? "", category: p.category, minScore: String(p.min_score ?? "") });
    setEditing(true);
    if (typeof window !== "undefined") window.scrollTo({ top: 0, behavior: "smooth" });
  }

  const EXPORT_COLS = ["Code", "Name", "Faculty", "Department", "Category", "Min Score"];
  const exportRows = () => programmes.map((p) => [p.code, p.name, p.faculty_name, p.department_name ?? "", p.category, p.min_score]);
  async function exportXlsx() {
    downloadBlob(await brandedXlsx("Programmes on the register", EXPORT_COLS, exportRows(), { serial: docSerial("PRG") }), "Programmes.xlsx");
  }
  function exportPdf() {
    brandedPrint("Programmes on the register", `${programmes.length} programmes`, EXPORT_COLS, exportRows(), docSerial("PRG"));
  }

  async function upload(file: File) {
    setMsg(null); setProblem(null);
    try {
      const grid = await xlsxRows(await file.arrayBuffer());
      const header = (grid[0] ?? []).map((c) => String(c ?? "").trim().toLowerCase());
      const at = (n: string[]) => header.findIndex((h) => n.some((x) => h.includes(x)));
      const ci = { code: at(["code"]), name: at(["name", "programme"]), faculty: at(["faculty"]), deptCode: at(["department code", "dept code"]), dept: at(["department", "dept"]), cat: at(["category"]), ms: at(["score", "minimum", "min"]) };
      if (ci.code < 0 || ci.name < 0 || ci.faculty < 0) { setProblem({ status: 400, title: "That file needs Code, Name and Faculty columns.", detail: "Download the template." }); return; }
      const g = (r: (string | number | null)[], i: number) => (i >= 0 ? String(r[i] ?? "").trim() : "");
      const rows = grid.slice(1).filter((r) => g(r, ci.code) && !/^code$/i.test(g(r, ci.code))).map((r) => ({
        code: g(r, ci.code), name: g(r, ci.name), faculty: g(r, ci.faculty),
        departmentCode: g(r, ci.deptCode), department: g(r, ci.dept), category: g(r, ci.cat), minScore: g(r, ci.ms),
      }));
      if (!rows.length) { setProblem({ status: 400, title: "No programmes found in the file." }); return; }
      const j = await post("/programmes/import", { rows }, `${rows.length} programmes uploaded`);
      if (j) { setMsg(`${j.saved ?? 0} programmes saved${(j.bad_code ?? 0) ? ` · ${j.bad_code} bad codes` : ""}${(j.no_faculty ?? 0) ? ` · ${j.no_faculty} with no matching faculty` : ""}.`); notify(`${j.saved ?? 0} programmes saved`); }
    } catch { setProblem({ status: 400, title: "That file could not be read as a spreadsheet." }); }
  }

  return (
    <>
      <RoleLine allowed={["academic", "registrar", "dregistrar"]} actingOffice={actingOffice} canAct={may} action="Creating and editing programmes" />
      <Note kind="info" title="Create a programme, or upload the list">
        A programme carries a code (<b>C</b> then five digits, e.g. C00101), a name and a faculty; a department is
        optional (it defaults to the faculty, and is created under it if new). Create one below or upload a spreadsheet.
        Faculties must exist first — add them on the Faculty upload/create screen. Uploading again updates, never duplicates.
      </Note>
      {!may ? <Note kind="bad" title="This desk is for the Directorate of ICT and the Academic Office">Your office may not manage programmes.</Note> : null}
      {problem ? <ProblemNotice problem={problem} /> : null}
      {msg ? <Note kind="ok" title="Programmes loaded">{msg}</Note> : null}

      <Tiles items={[
        ["Programmes", String(programmes.length), null, "On the register"],
        ["Faculties", String(faculties.length), null, "They hang off these"],
      ]} />

      {may ? (
        <Panel title={editing ? `Edit ${f.code}` : "Add a programme"} right="Or upload the list">
          <PBody>
            <div className="grid grid--3">
              <Field id="pg-code" label="Code" hint={editing ? "The code cannot change" : "C then five digits"}><input id="pg-code" className="ctl tnum" value={f.code} disabled={editing} onChange={(e) => setF({ ...f, code: e.target.value.toUpperCase() })} placeholder="C00101" /></Field>
              <Field id="pg-name" label="Name"><input id="pg-name" className="ctl" value={f.name} onChange={(e) => setF({ ...f, name: e.target.value })} placeholder="B.Sc. Computer Science" /></Field>
              <Field id="pg-fac" label="Faculty"><select id="pg-fac" className="ctl" value={f.faculty} onChange={(e) => setF({ ...f, faculty: e.target.value })}><option value="">Choose the faculty…</option>{faculties.map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}</select></Field>
            </div>
            <div className="grid grid--3">
              <Field id="pg-dc" label="Department code" hint="Optional; blank = the faculty"><input id="pg-dc" className="ctl tnum" value={f.deptCode} onChange={(e) => setF({ ...f, deptCode: e.target.value.toUpperCase() })} /></Field>
              <Field id="pg-dn" label="Department name" hint="Optional"><input id="pg-dn" className="ctl" value={f.department} onChange={(e) => setF({ ...f, department: e.target.value })} /></Field>
              <Field id="pg-cat" label="Category"><select id="pg-cat" className="ctl" value={f.category} onChange={(e) => setF({ ...f, category: e.target.value })}><option>UNDER GRADUATE</option><option>POST GRADUATE</option></select></Field>
            </div>
            <div className="grid grid--3">
              <Field id="pg-ms" label="Minimum score" hint="UTME cut-off floor, optional"><input id="pg-ms" className="ctl tnum" value={f.minScore} onChange={(e) => setF({ ...f, minScore: e.target.value.replace(/[^0-9]/g, "") })} placeholder="180" /></Field>
              <div /><div />
            </div>
            <div className="row">
              <Btn kind="primary" disabled={busy || !/^C[0-9]{5}$/.test(f.code.trim()) || !f.name.trim() || !f.faculty} onClick={async () => {
                const j = await post("/programmes", { code: f.code.trim(), name: f.name.trim(), faculty: f.faculty, departmentCode: f.deptCode || null, department: f.department || null, category: f.category, minScore: f.minScore ? Number(f.minScore) : null }, `Programme ${f.code.trim()} created`);
                if (j) { setMsg(`Programme ${j.code} saved.`); setF({ code: "", name: "", faculty: "", deptCode: "", department: "", category: "UNDER GRADUATE", minScore: "" }); setEditing(false); }
              }}>{editing ? "Save changes" : "Save the programme"}</Btn>
              {editing ? <Btn kind="ghost" onClick={() => { setF({ code: "", name: "", faculty: "", deptCode: "", department: "", category: "UNDER GRADUATE", minScore: "" }); setEditing(false); }}>Cancel</Btn> : null}
              <Btn kind="ghost" onClick={downloadTemplate}>Download template</Btn>
              <label className={`btn btn--ghost btn--sm${busy ? " btn--disabled" : ""}`} style={{ cursor: busy ? "not-allowed" : "pointer", margin: 0 }}>
                Upload programmes (.xlsx)
                <input type="file" accept=".xlsx" style={{ display: "none" }} disabled={busy} onChange={(e) => { const x = e.target.files?.[0]; if (x) void upload(x); e.target.value = ""; }} />
              </label>
            </div>
            {f.code && !/^C[0-9]{5}$/.test(f.code.trim()) ? <div className="sub2" style={{ marginTop: 6, color: "var(--red-ink)" }}>The code must be C followed by five digits, e.g. C00101.</div> : null}
          </PBody>
        </Panel>
      ) : null}

      <Panel title="Programmes" right={<span className="row">
        <span className="sub2">{programmes.length} on the register</span>
        <Btn kind="ghost" disabled={!programmes.length} onClick={() => void exportXlsx()}>Download Excel</Btn>
        <Btn kind="ghost" disabled={!programmes.length} onClick={exportPdf}>Download PDF</Btn>
      </span>}>
        {programmes.length ? (
          <DTable cols={["Code|mid", "Programme", "Faculty", "Department", "Category|mid", "Min|num", "|num"]} rows={programmes.map((p) => [
            <span className="tnum" key="c">{p.code}</span>,
            <strong key="n">{p.name}{p.archived ? <Pil kind="grey" key="a">archived</Pil> : null}</strong>,
            <span className="sub2" key="f">{p.faculty_name}</span>,
            <span className="sub2" key="d">{p.department_name ?? p.dept_code ?? "—"}</span>,
            <span className="sub2" key="cat">{p.category === "POST GRADUATE" ? "PG" : "UG"}</span>,
            <span className="tnum" key="m">{p.min_score}</span>,
            may ? <span key="x" style={{ display: "flex", gap: 6, justifyContent: "flex-end", flexWrap: "wrap" }}>
              <IcoBtn key="e" icon="edit" label={`Edit ${p.name}`} disabled={busy} onClick={() => edit(p)} />
              <Btn kind="ghost" disabled={busy} onClick={() => void archive(p, !p.archived)}>{p.archived ? "Restore" : "Archive"}</Btn>
              <IcoBtn key="x" icon="trash" danger label={`Delete ${p.name} (only if nothing hangs on it)`} disabled={busy} onClick={() => void remove(p)} />
            </span> : <span className="sub2" key="x">—</span>,
          ])} texts={programmes.map((p) => `${p.code} ${p.name} ${p.faculty_name}`)} />
        ) : <PBody><div className="sub2">No programme yet. Add one above.</div></PBody>}
      </Panel>
    </>
  );
}
