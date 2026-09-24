"use client";

/** t/facultyupload — create a faculty, or upload a list of them (V091). ICT/Academic and structure offices. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify } from "@/components/proto/Toast";
import { xlsxRows, buildXlsx } from "@/lib/xlsx";
import { brandedXlsx, brandedPrint, downloadBlob, docSerial } from "@/lib/exportbrand";
import { Btn, IcoBtn, Note, Panel, PBody, RoleLine, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface Faculty { code: string; name: string; departments: number; programmes: number }
const MAY = ["ict", "super", "admin", "academic", "registrar", "dregistrar"];

export function Faculties({ faculties, actingOffice }: { faculties: Faculty[]; actingOffice: string | null }) {
  const router = useRouter();
  const may = MAY.includes(actingOffice ?? "");
  const [code, setCode] = useState("");
  const [name, setName] = useState("");
  const [editing, setEditing] = useState(false);
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [msg, setMsg] = useState<string | null>(null);

  function downloadTemplate() {
    const blob = buildXlsx(["Code", "Name"], [["SCI", "Faculty of Science (example — delete this row)"]], "Faculties");
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = "Faculties template.xlsx";
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

  async function remove(fac: Faculty) {
    if (fac.programmes || fac.departments) { setProblem({ status: 400, title: `${fac.name} still has ${fac.programmes} programme(s) and ${fac.departments} department(s).`, detail: "Remove or move them first; a faculty is deleted only when it is empty." }); return; }
    if (!window.confirm(`Remove ${fac.name}? This cannot be undone.`)) return;
    setBusy(true); setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/catalogue/faculties/${encodeURIComponent(fac.code)}`, { method: "DELETE", headers: { "X-Reason": reasonHeader(`Faculty ${fac.code} removed`) } });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j ?? { status: r.status, title: r.statusText }); return; }
      setMsg(`Faculty ${fac.code} removed.`); notify(`Faculty ${fac.code} removed`); router.refresh();
    } finally { setBusy(false); }
  }

  const EXPORT_COLS = ["Code", "Name", "Departments", "Programmes"];
  const exportRows = () => faculties.map((f) => [f.code, f.name, f.departments, f.programmes]);
  async function exportXlsx() {
    downloadBlob(await brandedXlsx("Faculties on the register", EXPORT_COLS, exportRows(), { serial: docSerial("FAC") }), "Faculties.xlsx");
  }
  function exportPdf() {
    brandedPrint("Faculties on the register", `${faculties.length} faculties`, EXPORT_COLS, exportRows(), docSerial("FAC"));
  }

  async function upload(file: File) {
    setMsg(null); setProblem(null);
    try {
      const grid = await xlsxRows(await file.arrayBuffer());
      const header = (grid[0] ?? []).map((c) => String(c ?? "").trim().toLowerCase());
      const at = (n: string[]) => header.findIndex((h) => n.some((x) => h.includes(x)));
      const ci = { code: at(["code"]), name: at(["name"]) };
      if (ci.code < 0 || ci.name < 0) { setProblem({ status: 400, title: "That file needs Code and Name columns.", detail: "Download the template." }); return; }
      const rows = grid.slice(1).map((r) => ({ code: String(r[ci.code] ?? "").trim(), name: String(r[ci.name] ?? "").trim() })).filter((r) => r.code && !/^code$/i.test(r.code));
      if (!rows.length) { setProblem({ status: 400, title: "No faculties found in the file." }); return; }
      const j = await post("/faculties/import", { rows }, `${rows.length} faculties uploaded`);
      if (j) { setMsg(`${j.saved ?? 0} faculties saved${(j.bad ?? 0) ? ` · ${j.bad} rows had no name` : ""}.`); notify(`${j.saved ?? 0} faculties saved`); }
    } catch { setProblem({ status: 400, title: "That file could not be read as a spreadsheet." }); }
  }

  return (
    <>
      <RoleLine allowed={["academic", "registrar", "dregistrar"]} actingOffice={actingOffice} canAct={may} action="Creating and editing faculties" />
      <Note kind="info" title="Create a faculty, or upload the list">
        A faculty is a code and a name. Create one below, or upload a spreadsheet of them. Uploading again updates rather
        than duplicates; every change is on the record in your name. Programmes and departments hang off the faculty.
      </Note>
      {!may ? <Note kind="bad" title="This desk is for the Directorate of ICT and the Academic Office">Your office may not manage faculties.</Note> : null}
      {problem ? <ProblemNotice problem={problem} /> : null}
      {msg ? <Note kind="ok" title="Faculties loaded">{msg}</Note> : null}

      <Tiles items={[["Faculties", String(faculties.length), null, "On the register"]]} cls="grid--4" />

      {may ? (
        <Panel title={editing ? `Edit ${code}` : "Add a faculty"} right="Or upload the list">
          <PBody>
            <div className="grid grid--2">
              <Field id="fc-code" label="Code" hint={editing ? "The code cannot change" : "Short, e.g. SCI"}><input id="fc-code" className="ctl tnum" value={code} disabled={editing} onChange={(e) => setCode(e.target.value.toUpperCase())} /></Field>
              <Field id="fc-name" label="Name"><input id="fc-name" className="ctl" value={name} onChange={(e) => setName(e.target.value)} placeholder="Faculty of Science" /></Field>
            </div>
            <div className="row">
              <Btn kind="primary" disabled={busy || !code.trim() || !name.trim()} onClick={async () => { const j = await post("/faculties", { code: code.trim(), name: name.trim() }, `Faculty ${code.trim()} ${editing ? "edited" : "created"}`); if (j) { setMsg(`Faculty ${j.code} saved.`); setCode(""); setName(""); setEditing(false); } }}>{editing ? "Save changes" : "Save the faculty"}</Btn>
              {editing ? <Btn kind="ghost" onClick={() => { setCode(""); setName(""); setEditing(false); }}>Cancel</Btn> : null}
              <Btn kind="ghost" onClick={downloadTemplate}>Download template</Btn>
              <label className={`btn btn--ghost btn--sm${busy ? " btn--disabled" : ""}`} style={{ cursor: busy ? "not-allowed" : "pointer", margin: 0 }}>
                Upload faculties (.xlsx)
                <input type="file" accept=".xlsx" style={{ display: "none" }} disabled={busy} onChange={(e) => { const f = e.target.files?.[0]; if (f) void upload(f); e.target.value = ""; }} />
              </label>
            </div>
          </PBody>
        </Panel>
      ) : null}

      <Panel title="Faculties" right={<span className="row">
        <span className="sub2">{faculties.length} on the register</span>
        <Btn kind="ghost" disabled={!faculties.length} onClick={() => void exportXlsx()}>Download Excel</Btn>
        <Btn kind="ghost" disabled={!faculties.length} onClick={exportPdf}>Download PDF</Btn>
      </span>}>
        {faculties.length ? (
          <DTable cols={["Code|mid", "Name", "Departments|num", "Programmes|num", "|num"]} rows={faculties.map((f) => [
            <span className="tnum" key="c">{f.code}</span>, <strong key="n">{f.name}</strong>,
            <span className="tnum" key="d">{f.departments}</span>, <span className="tnum" key="p">{f.programmes}</span>,
            may ? <span key="x" style={{ display: "flex", gap: 6, justifyContent: "flex-end" }}>
              <IcoBtn key="e" icon="edit" label={`Edit ${f.name}`} disabled={busy} onClick={() => { setCode(f.code); setName(f.name); setEditing(true); if (typeof window !== "undefined") window.scrollTo({ top: 0, behavior: "smooth" }); }} />
              <IcoBtn key="x" icon="trash" danger label={f.programmes || f.departments ? "Empty the faculty first" : `Remove ${f.name}`} disabled={busy || !!f.programmes || !!f.departments} onClick={() => void remove(f)} />
            </span> : <span className="sub2" key="x">—</span>,
          ])} texts={faculties.map((f) => `${f.code} ${f.name}`)} />
        ) : <PBody><div className="sub2">No faculty yet. Add one above.</div></PBody>}
      </Panel>
    </>
  );
}
