"use client";
/** V487: prerequisites uploaded in bulk — a template of (course, requires) rows, the file previewed row by row (nothing kept),
 *  then imported. A row closing a loop, naming a course the pool does not hold, or another department's course is reported and
 *  not written; a prerequisite already recorded is said so. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { reasonHeader } from "@/lib/reason";
import { xlsxRows, csvRows, buildXlsx } from "@/lib/xlsx";
import { downloadBlob } from "@/lib/exportbrand";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

interface Row { row_no: number; course_in: string; requires_in: string; course_code: string | null; requires_code: string | null; outcome: string; message: string }
interface Loaded { total: number; counts: Record<string, number>; added: number; rows: Row[] }

const OUTCOME: Record<string, [string, "ok" | "info" | "warn" | "bad" | "grey"]> = {
  ADDED: ["Added", "ok"], ALREADY: ["Already recorded", "grey"], NO_COURSE: ["No such course", "bad"], NO_REQUIRED: ["No such prerequisite", "bad"],
  SELF: ["Requires itself", "bad"], CYCLE: ["Would loop", "bad"], REFUSED: ["Refused", "bad"], INCOMPLETE: ["Incomplete row", "bad"],
  OUTSIDE_SCOPE: ["Another department's", "bad"],
};

async function post(path: string, rows: { course: string; requires: string }[], reason: string): Promise<Loaded | null> {
  const r = await fetch(`/api/bff/api/v1/catalogue/prerequisites/${path}`, {
    method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify({ rows }),
  });
  const j = await r.json().catch(() => null);
  if (!r.ok) { notifyProblem(j && typeof j === "object" && "status" in j ? j : { status: r.status, title: r.statusText }); return null; }
  return j as Loaded;
}

export function PrerequisiteUpload() {
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [file, setFile] = useState<{ name: string; rows: { course: string; requires: string }[] } | null>(null);
  const [preview, setPreview] = useState<Loaded | null>(null);
  const [done, setDone] = useState<Loaded | null>(null);

  function template() {
    downloadBlob(buildXlsx(["Course code", "Requires (course code)"], [["CSC 201", "CSC 101"], ["CSC 201", "MTH 101"]], "Prerequisites"), "prerequisites-template.xlsx");
  }

  async function read(f: File) {
    setBusy(true); setPreview(null); setDone(null);
    try {
      const isCsv = /\.csv$/i.test(f.name) || f.type === "text/csv";
      const grid = isCsv ? csvRows(await f.text()) : await xlsxRows(await f.arrayBuffer());
      const head = (grid[0] ?? []).map((c) => String(c ?? "").trim().toLowerCase());
      const ci = head.findIndex((h) => /^course( code)?$/.test(h) || (h.includes("course") && !h.includes("require")));
      const ri = head.findIndex((h) => h.includes("require") || h.includes("prerequisite"));
      if (ci < 0 || ri < 0) {
        notifyProblem({ status: 400, title: "The file needs a Course code column and a Requires column.", detail: "Download the template to see them." });
        return;
      }
      const rows = grid.slice(1).map((g) => ({ course: String(g[ci] ?? "").trim(), requires: String(g[ri] ?? "").trim() })).filter((x) => x.course || x.requires);
      if (!rows.length) { notifyProblem({ status: 400, title: "No rows to read.", detail: "Fill the template and upload it." }); return; }
      setFile({ name: f.name, rows });
      const p = await post("upload/preview", rows, `Prerequisites previewed from ${f.name}: ${rows.length} rows`);
      if (p) setPreview(p);
    } catch {
      notifyProblem({ status: 400, title: "That file could not be read as a spreadsheet.", detail: "Upload the .xlsx built from the template, or a .csv." });
    } finally { setBusy(false); }
  }

  async function confirm() {
    if (!file) return;
    setBusy(true);
    try {
      const d = await post("upload", file.rows, `Prerequisites uploaded from ${file.name}: ${file.rows.length} rows`);
      if (d) {
        notify(`${d.added} prerequisite${d.added === 1 ? "" : "s"} added`);
        setDone(d); setPreview(null); setFile(null);
        router.refresh();
      }
    } finally { setBusy(false); }
  }

  const shown = preview ?? done;
  return (
    <Panel title="Upload prerequisites" right={shown ? (preview ? "Preview — nothing has been written" : "Imported") : "Course code · the course it requires"}>
      <PBody>
        <div className="sub2">
          One row a prerequisite: the course, and a course a student passes before registering it. Each row is checked as the course page checks it —
          a course the pool does not hold, a course requiring itself, and a row that would close a loop are refused — and a course is uploaded only by an office that sets its prerequisites.
        </div>
        <div className="row mt-2">
          <Btn kind="ghost" onClick={template}>Download template</Btn>
          <label className={`btn btn--primary btn--sm${busy ? " btn--disabled" : ""}`} style={{ cursor: busy ? "not-allowed" : "pointer", margin: 0 }}>
            {busy && !preview ? "Reading…" : "Upload prerequisites (.xlsx / .csv)"}
            <input type="file" accept=".xlsx,.csv" style={{ display: "none" }} disabled={busy} onChange={(e) => { const f = e.target.files?.[0]; if (f) void read(f); e.target.value = ""; }} />
          </label>
        </div>
        {shown ? (
          <div className="mt-3">
            <Tiles cls="grid--4" items={[
              ["Rows", String(shown.total), null, file?.name ?? "In the file"],
              [preview ? "To add" : "Added", String(shown.counts.ADDED ?? 0), "var(--green-ink)", "Prerequisites recorded"],
              ["Already recorded", String(shown.counts.ALREADY ?? 0), null, "Left as they are"],
              ["Refused", String(shown.total - (shown.counts.ADDED ?? 0) - (shown.counts.ALREADY ?? 0)), shown.total - (shown.counts.ADDED ?? 0) - (shown.counts.ALREADY ?? 0) ? "var(--red-ink)" : null, "Not written"],
            ]} />
            {preview ? (
              <div className="row mt-2">
                <Btn kind="go" disabled={busy || !(preview.counts.ADDED ?? 0)} busyLabel="Importing…" onClick={() => void confirm()}>{`Import ${preview.counts.ADDED ?? 0} prerequisite${(preview.counts.ADDED ?? 0) === 1 ? "" : "s"}`}</Btn>
                <Btn kind="ghost" disabled={busy} onClick={() => { setPreview(null); setFile(null); }}>Cancel</Btn>
              </div>
            ) : null}
          </div>
        ) : null}
      </PBody>
      {shown ? (
        <DTable cols={["Row|num", "Course", "Requires", "Outcome|mid", "What happens"]} rows={shown.rows.map((r) => [
          <span key="n" className="tnum sub2">{r.row_no}</span>,
          <b key="c" className="tnum">{r.course_code || r.course_in}</b>,
          <span key="q" className="tnum">{r.requires_code || r.requires_in}</span>,
          <Pil key="o" kind={OUTCOME[r.outcome]?.[1] ?? "grey"}>{OUTCOME[r.outcome]?.[0] ?? r.outcome}</Pil>,
          <span key="m" className="sub2">{r.message}</span>,
        ])} texts={shown.rows.map((r) => `${r.course_code ?? r.course_in} ${r.requires_code ?? r.requires_in} ${r.outcome}`)} />
      ) : null}
    </Panel>
  );
}
