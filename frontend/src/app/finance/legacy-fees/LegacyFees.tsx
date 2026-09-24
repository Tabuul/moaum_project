"use client";

/** t/legacyfees — old students' school-fees history from the old portal (V087). Each row settles a past
 *  session (or semester) by the amount paid, or in full against the fee schedule when the amount is blank.
 *  Columns are matched by keyword, so a template or an old-portal export both read. Bursary only. */
import { useState } from "react";
import { reasonHeader } from "@/lib/reason";
import type { Problem } from "@/lib/api";
import { xlsxRows, buildXlsx } from "@/lib/xlsx";
import { Btn, Note, Panel, PBody, Tiles } from "@/components/proto/ui";
import { ProblemNotice } from "@/components/ProblemNotice";

interface Row { matric: string; session: string; semester: string; amount: string; paidOn: string; receiptNo: string; note: string }
const MAY = ["bursar", "super", "admin"];

export function LegacyFees({ actingOffice }: { actingOffice: string | null }) {
  const may = MAY.includes(actingOffice ?? "");
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [preview, setPreview] = useState<Row[] | null>(null);
  const [result, setResult] = useState<Record<string, number> | null>(null);
  const [progress, setProgress] = useState<string | null>(null);

  function downloadTemplate() {
    const blob = buildXlsx(
      ["Matriculation Number", "Session", "Semester", "Amount Paid", "Paid On", "Receipt No", "Note"],
      [
        ["MOAUM/CSC/22/0001", "2022/2023", "1", "85000", "2022-11-04", "OLD-000123", "First semester fees"],
        ["MOAUM/CSC/22/0001", "2022/2023", "2", "", "2023-03-12", "", "Cleared in full (amount left blank)"],
      ],
      "Old fees history",
    );
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = "Old fees history template.xlsx";
    document.body.appendChild(a);
    a.click();
    a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  }

  async function read(file: File) {
    setBusy(true);
    setProblem(null);
    setResult(null);
    setPreview(null);
    try {
      const grid = await xlsxRows(await file.arrayBuffer());
      const header = (grid[0] ?? []).map((c) => String(c ?? "").trim().toLowerCase());
      const at = (names: string[]) => header.findIndex((h) => names.some((n) => h.includes(n)));
      const ci = { matric: at(["matric", "reg"]), session: at(["session"]), sem: at(["semester", "sem"]), amount: at(["amount"]), paidOn: at(["paid on", "date"]), receipt: at(["receipt"]), note: at(["note"]) };
      if (ci.matric < 0 || ci.session < 0) {
        setProblem({ status: 400, title: "That file has no matriculation-number and session columns.", detail: "Download the template, or upload the old-portal export with those columns." });
        return;
      }
      const g = (r: (string | number | null)[], i: number) => (i >= 0 ? String(r[i] ?? "").trim() : "");
      const rows = grid.slice(1)
        .filter((r) => g(r, ci.matric) && /^[0-9]{4}\/[0-9]{4}$/.test(g(r, ci.session)))
        .map((r) => ({ matric: g(r, ci.matric), session: g(r, ci.session), semester: g(r, ci.sem), amount: g(r, ci.amount), paidOn: g(r, ci.paidOn), receiptNo: g(r, ci.receipt), note: g(r, ci.note) }));
      if (!rows.length) { setProblem({ status: 400, title: "No fee rows were found in that file.", detail: "Each row needs a matriculation number and a session (YYYY/YYYY)." }); return; }
      setPreview(rows);
    } catch {
      setProblem({ status: 400, title: "That file could not be read as a spreadsheet.", detail: "Use the downloaded template (.xlsx)." });
    } finally {
      setBusy(false);
    }
  }

  async function upload() {
    if (!preview) return;
    setBusy(true);
    setProblem(null);
    setResult(null);
    const CHUNK = 500;   // a whole file of tens of thousands of rows in one body is refused ("Failed to read request")
    const totals: Record<string, number> = { rows: 0, cleared: 0, no_student: 0, no_due: 0 };
    try {
      for (let i = 0; i < preview.length; i += CHUNK) {
        const batch = preview.slice(i, i + CHUNK);
        setProgress(`Loading ${Math.min(i + batch.length, preview.length).toLocaleString()} of ${preview.length.toLocaleString()} rows…`);
        const r = await fetch("/api/bff/api/v1/finance/legacy-fees", {
          method: "POST",
          headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Old students' school-fees history imported: rows ${i + 1}–${i + batch.length}`) },
          body: JSON.stringify({ rows: batch }),
        });
        const j = await r.json().catch(() => null);
        if (!r.ok) {
          const base = (j ?? { status: r.status, title: r.statusText }) as Problem;
          setProblem({ ...base, detail: `${base.detail ? base.detail + " " : ""}${totals.cleared.toLocaleString()} payments were settled before this batch was refused. The import is idempotent — fix and upload again.` });
          return;
        }
        const c = (j ?? {}) as Record<string, number>;
        totals.rows += c.rows ?? 0; totals.cleared += c.cleared ?? 0;
        totals.no_student += c.no_student ?? 0; totals.no_due += c.no_due ?? 0;
      }
      setResult(totals);
      setPreview(null);
    } finally {
      setBusy(false);
      setProgress(null);
    }
  }

  return (
    <>
      <Note kind="info" title="Clear old students' school-fees history from the old portal">
        A returning student brought over from the old portal owes every past session the University has a fee schedule
        for, because the new portal knows only its own confirmed payments. Upload what each student already paid, by
        session and (optionally) semester. Give the <b>amount paid</b>, or leave it blank to mean <b>cleared in full</b> —
        the past session then settles and the arrears clear. Re-uploading the same file updates rather than duplicates,
        and every record is on the audit spine in your name.
      </Note>
      {!may ? <Note kind="bad" title="This desk is for the Bursary">Your office may not import fees history.</Note> : null}

      <Panel title="Old-portal fees export" right="Matriculation number · session · amount (or blank for cleared)">
        <PBody>
          <div className="row">
            <Btn kind="ghost" onClick={downloadTemplate}>Download template</Btn>
            <label className={`btn btn--primary m-0${!may || busy ? " btn--disabled" : ""}`} style={{ cursor: may && !busy ? "pointer" : "not-allowed", opacity: !may ? 0.6 : 1 }}>
              {busy ? "Reading…" : "Choose the fees file (.xlsx)"}
              <input type="file" accept=".xlsx" style={{ display: "none" }} disabled={!may || busy} onChange={(e) => { const f = e.target.files?.[0]; if (f) void read(f); e.target.value = ""; }} />
            </label>
          </div>
          <div className="sub2 mt-2">Columns read: Matriculation Number, Session (YYYY/YYYY), Semester (1/2, optional), Amount Paid (blank = cleared in full), Paid On and Receipt No (optional). Columns are matched by name, so an old-portal export with those columns can be uploaded as-is.</div>
        </PBody>
      </Panel>

      {problem ? <ProblemNotice problem={problem} /> : null}
      {result ? (
        <>
          <Tiles items={[
            ["Rows read", String(result.rows ?? 0), null, "In the file"],
            ["Settled", String(result.cleared ?? 0), "var(--green-ink)", "Payments recorded"],
            ["No such student", String(result.no_student ?? 0), (result.no_student ?? 0) ? "var(--red-ink)" : null, "Import the students first"],
            ["Nothing to settle", String(result.no_due ?? 0), null, "No amount and no fee schedule"],
          ]} />
          <Note kind="ok" title="Fees history imported">{result.cleared ?? 0} past-session payment{(result.cleared ?? 0) === 1 ? "" : "s"} recorded. The students&rsquo; positions and arrears update at once.{(result.no_student ?? 0) > 0 ? " Rows with an unknown number are counted above — migrate those students first, then re-upload." : ""}</Note>
        </>
      ) : null}

      {preview ? (
        <Panel title="Read from the file — check, then load" right={`${preview.length} row${preview.length === 1 ? "" : "s"}`}>
          <PBody>
            <div className="tablewrap" style={{ maxHeight: 260, overflowY: "auto", border: "1px solid var(--line)", borderRadius: "var(--r-md)" }}>
              <table className="tbl--data">
                <thead><tr><th>Matric</th><th>Session</th><th>Sem</th><th>Amount</th><th>Paid on</th></tr></thead>
                <tbody>
                  {preview.slice(0, 200).map((r, i) => (
                    <tr key={i}><td className="tnum">{r.matric}</td><td className="tnum">{r.session}</td><td className="tnum">{r.semester || "—"}</td><td className="tnum">{r.amount || "cleared in full"}</td><td className="sub2">{r.paidOn || "—"}</td></tr>
                  ))}
                </tbody>
              </table>
            </div>
            <div className="row mt-3">
              <Btn kind="primary" size="md" disabled={busy || !may} onClick={() => void upload()}>{busy ? (progress ?? "Loading…") : `Load ${preview.length.toLocaleString()} rows`}</Btn>
              <Btn kind="ghost" size="md" disabled={busy} onClick={() => setPreview(null)}>Cancel</Btn>
              {busy && progress ? <span className="sub2">{progress}</span> : null}
            </div>
          </PBody>
        </Panel>
      ) : null}
    </>
  );
}
