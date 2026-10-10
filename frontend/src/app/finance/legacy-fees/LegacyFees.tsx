"use client";

import { notifyProblem } from "@/components/proto/Toast";
/** t/legacyfees — old students' school-fees history from the old portal (V087). Each row settles a past
 *  session (or semester) by the amount paid, or in full against the fee schedule when the amount is blank.
 *  Columns are matched by keyword, so a template or an old-portal export both read. Bursary only. */
import { useRef, useState } from "react";
import { reasonHeader } from "@/lib/reason";
import type { Problem } from "@/lib/api";
import { xlsxRows, buildXlsx } from "@/lib/xlsx";
import { Btn, Note, Panel, PBody, Tiles } from "@/components/proto/ui";
import { ProblemNotice } from "@/components/ProblemNotice";

import { legacyFeeKind, legacyFeeRows, type LegacyFeeRow as Row } from "@/lib/legacy-fees";
const MAY = ["bursar", "super", "admin"];

export function LegacyFees({ actingOffice }: { actingOffice: string | null }) {
  const may = MAY.includes(actingOffice ?? "");
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [preview, setPreview] = useState<Row[] | null>(null);
  const [result, setResult] = useState<Record<string, number> | null>(null);
  const [progress, setProgress] = useState<string | null>(null);
  const [duplicateSample, setDuplicateSample] = useState<string[]>([]);
  const [resetSession, setResetSession] = useState("");
  const [resetWord, setResetWord] = useState("");
  const [loaded, setLoaded] = useState<{ payments: number; students: number; total: number; sessions: string; session: string } | null>(null);
  const [resetDone, setResetDone] = useState<string | null>(null);
  const [resumeAt, setResumeAt] = useState<number | null>(null);
  const jobRef = useRef<{ rows: Row[]; at: number; totals: Record<string, number>; sample: string[] } | null>(null);

  function downloadTemplate() {
    const blob = buildXlsx(
      ["Matriculation Number", "Session", "Semester", "Level", "Amount Paid", "Purpose / Payment Item", "Paid On", "Receipt No", "Note"],
      [
        ["MOAUM/CSC/22/0001", "2022/2023", "First", "100", "85000", "SCHOOL FEES", "2022-11-04", "OLD-000123", ""],
        ["MOAUM/CSC/22/0001", "2022/2023", "Second", "", "", "SCHOOL FEES", "2023-03-12", "", "Cleared in full (amount left blank)"],
        ["MOAUM/CSC/22/0001", "2022/2023", "Session", "", "4000", "GST FEES", "2022-11-20", "OLD-000456", ""],
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
    setDuplicateSample([]);
    setResumeAt(null);
    jobRef.current = null;
    setPreview(null);
    try {
      const grid = await xlsxRows(await file.arrayBuffer());
      /* V326: the columns are matched by keyword in lib/legacy-fees — the old portal's export (Purpose/Payment Item,
         Payment Date, Channel, Reference) reads as well as the template */
      const { columns: ci, rows } = legacyFeeRows(grid);
      if (ci.matric < 0 || ci.session < 0) {
        setProblem({ status: 400, title: "That file has no matriculation-number and session columns.", detail: "Download the template, or upload the old-portal export with those columns." }); notifyProblem({ status: 400, title: "That file has no matriculation-number and session columns.", detail: "Download the template, or upload the old-portal export with those columns." });
        return;
      }
      if (!rows.length) { setProblem({ status: 400, title: "No fee rows were found in that file.", detail: "Each row needs a matriculation number and a session (YYYY/YYYY)." }); notifyProblem({ status: 400, title: "No fee rows were found in that file.", detail: "Each row needs a matriculation number and a session (YYYY/YYYY)." }); return; }
      setPreview(rows);
    } catch {
      setProblem({ status: 400, title: "That file could not be read as a spreadsheet.", detail: "Use the downloaded template (.xlsx)." }); notifyProblem({ status: 400, title: "That file could not be read as a spreadsheet.", detail: "Use the downloaded template (.xlsx)." });
    } finally {
      setBusy(false);
    }
  }

  function downloadDuplicates() {
    const csv = ["reference", ...duplicateSample].join("\n") + "\n";
    const a = document.createElement("a");
    a.href = URL.createObjectURL(new Blob([csv], { type: "text/csv" }));
    a.download = "legacy-fees-already-on-record.csv";
    a.click();
    URL.revokeObjectURL(a.href);
  }

  async function sendBatch(batch: Row[], from: number, total: number) {
    const waits = [2000, 5000, 15000];
    let last: Problem = { status: 0, title: "The batch was not sent" };
    for (let attempt = 0; attempt <= waits.length; attempt++) {
      try {
        const r = await fetch("/api/bff/api/v1/finance/legacy-fees", {
          method: "POST",
          headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Old students' school-fees history imported: rows ${from + 1}–${from + batch.length} of ${total}`) },
          body: JSON.stringify({ rows: batch }),
        });
        const j = await r.json().catch(() => null);
        if (r.ok) return { ok: true as const, counts: (j ?? {}) as Record<string, number> & { duplicate_sample?: string } };
        last = (j ?? { status: r.status, title: r.statusText || "The server refused this batch" }) as Problem;
        if (!(r.status === 408 || r.status === 429 || r.status >= 500)) break;
      } catch {
        last = { status: 0, title: "The connection to the portal dropped", detail: "The request never reached the server (network, timeout or an expired sign-in)." };
      }
      if (attempt < waits.length) {
        setProgress(`Batch refused (${last.status || "no connection"}), retrying ${attempt + 1} of ${waits.length}…`);
        await new Promise((res) => setTimeout(res, waits[attempt]));
      }
    }
    return { ok: false as const, problem: last };
  }

  /* runs, or resumes, the load from the saved position; a batch that cannot be sent stops it with the rows named */
  async function run() {
    const job = jobRef.current;
    if (!job) return;
    setBusy(true);
    setProblem(null);
    setResult(null);
    setResumeAt(null);
    const CHUNK = 500;   // a whole file of tens of thousands of rows in one body is refused ("Failed to read request")
    try {
      while (job.at < job.rows.length) {
        const batch = job.rows.slice(job.at, job.at + CHUNK);
        setProgress(`Loading ${Math.min(job.at + batch.length, job.rows.length).toLocaleString()} of ${job.rows.length.toLocaleString()} rows…`);
        const res = await sendBatch(batch, job.at, job.rows.length);
        if (!res.ok) {
          const where = `Rows ${(job.at + 1).toLocaleString()} to ${(job.at + batch.length).toLocaleString()} of ${job.rows.length.toLocaleString()}`;
          const base = res.problem;
          setProblem({ ...base, detail: `${where} could not be imported${base.status ? ` (HTTP ${base.status})` : ""}${base.detail ? `: ${base.detail}` : ""}. ${job.totals.cleared.toLocaleString()} payments were settled so far. Press Resume to carry on from this batch; the import is idempotent, so nothing duplicates.` });
          setResumeAt(job.at);
          return;
        }
        const c = res.counts;
        job.totals.rows += c.rows ?? 0; job.totals.cleared += c.cleared ?? 0;
        job.totals.no_student += c.no_student ?? 0; job.totals.no_due += c.no_due ?? 0; job.totals.duplicates += c.duplicates ?? 0;
        job.totals.corrected += c.corrected ?? 0; job.totals.undated += c.undated ?? 0;
        if (c.duplicate_sample) job.sample.push(...c.duplicate_sample.split(", "));
        job.at += batch.length;
      }
      setResult({ ...job.totals });
      setDuplicateSample(job.sample);
      setPreview(null);
      jobRef.current = null;
    } finally {
      setBusy(false);
      setProgress(null);
    }
  }

  async function checkLoaded() {
    setBusy(true); setProblem(null); setResetDone(null); setResetWord("");
    try {
      const q = resetSession.trim() ? `?session=${encodeURIComponent(resetSession.trim())}` : "";
      const r = await fetch(`/api/bff/api/v1/finance/legacy-fees/loaded${q}`);
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem((j ?? { status: r.status, title: r.statusText }) as Problem); return; }
      setLoaded({ ...(j as { payments: number; students: number; total: number; sessions: string }), session: resetSession.trim() });
    } finally { setBusy(false); }
  }

  async function resetAll() {
    if (!loaded) return;
    setBusy(true); setProblem(null);
    try {
      const r = await fetch("/api/bff/api/v1/finance/legacy-fees/reset", {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(`Old-portal fees history reset${loaded.session ? ` for ${loaded.session}` : ""} to be loaded again`) },
        body: JSON.stringify({ session: loaded.session || null, confirm: resetWord }),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem((j ?? { status: r.status, title: r.statusText }) as Problem); return; }
      const d = j as { deleted: number; kept_in_use: number };
      setResetDone(`${Number(d.deleted).toLocaleString()} imported payment${Number(d.deleted) === 1 ? "" : "s"} deleted${loaded.session ? ` for ${loaded.session}` : ""}.${d.kept_in_use ? ` ${d.kept_in_use} kept because a deferment fee uses them.` : ""} Upload the file again from the start.`);
      setLoaded(null); setResetWord(""); setResult(null);
    } finally { setBusy(false); }
  }

  function upload() {
    if (!preview) return;
    jobRef.current = { rows: preview, at: 0, totals: { rows: 0, cleared: 0, no_student: 0, no_due: 0, duplicates: 0, corrected: 0, undated: 0 }, sample: [] };
    void run();
  }

  return (
    <>
      <Note kind="info" title="Clear old students' school-fees history from the old portal">
        Upload what each student already paid, by session and (optionally) semester. A blank <b>amount</b> means <b>cleared in full</b>.
        The <b>Purpose / Payment Item</b> column sets what each payment was for: <b>GST FEES</b> is the GST fee, SCHOOL FEES is
        school fees, any other item does not clear school-fee arrears. A row already on record is skipped, never overwritten;
        loading the same export again is safe.
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
          <div className="sub2 mt-2">Columns read: Matriculation Number, Session (YYYY/YYYY), Semester (First/Second/1/2, or Session for the whole session; optional), Level (optional; otherwise worked out for that session), Amount (blank = cleared in full), Purpose / Payment Item (SCHOOL FEES, GST FEES, …), Paid On / Payment Date, Reference / Receipt No, Channel and Note (optional). Matched by name; the old portal&rsquo;s export uploads as-is.</div>
        </PBody>
      </Panel>

      {problem ? <ProblemNotice problem={problem} /> : null}
      {resetDone ? <Note kind="ok" title="Reset done">{resetDone}</Note> : null}
      {resumeAt !== null && preview ? (
        <Note kind="info" title={`Stopped at row ${resumeAt.toLocaleString()} of ${preview.length.toLocaleString()}`}
              action={<Btn kind="primary" disabled={busy} onClick={() => void run()}>Resume from the failed batch</Btn>}>
          If you reload the page, choose the file again; re-uploading is safe.
        </Note>
      ) : null}
      {result ? (
        <>
          <Tiles items={[
            ["Rows read", String(result.rows ?? 0), null, "In the file"],
            ["Settled", String(result.cleared ?? 0), "var(--green-ink)", "Payments recorded"],
            ["No such student", String(result.no_student ?? 0), (result.no_student ?? 0) ? "var(--red-ink)" : null, "Import the students first"],
            ["Nothing to settle", String(result.no_due ?? 0), null, "No amount and no fee schedule"],
            ["Already on record", String(result.duplicates ?? 0), (result.duplicates ?? 0) ? "var(--red-ink)" : null, "Skipped, not overwritten"],
            ["Corrected", String(result.corrected ?? 0), (result.corrected ?? 0) ? "var(--green-ink)" : null, "Date, semester or purpose fixed on a record already imported"],
            ["No usable date", String(result.undated ?? 0), (result.undated ?? 0) ? "var(--red-ink)" : null, "Loaded, dated today"],
          ]} />
          {(result.duplicates ?? 0) > 0 ? (
            <Note kind="bad" title="Rows already on record were skipped">
              {result.duplicates} row{result.duplicates === 1 ? "" : "s"} already recorded; nothing changed. First references: {duplicateSample.slice(0, 20).join(", ")}{duplicateSample.length > 20 ? ", …" : ""}. <button type="button" className="btn btn--ghost" onClick={downloadDuplicates}>Download all {duplicateSample.length.toLocaleString()} as CSV</button>
            </Note>
          ) : null}
          <Note kind="ok" title="Fees history imported">{result.cleared ?? 0} past-session payment{(result.cleared ?? 0) === 1 ? "" : "s"} recorded.{(result.no_student ?? 0) > 0 ? " Rows with an unknown number: migrate those students first, then re-upload." : ""}</Note>
        </>
      ) : null}

      {preview ? (
        <Panel title="Read from the file — check, then load" right={`${preview.length} row${preview.length === 1 ? "" : "s"}`}>
          <PBody>
            <div className="tablewrap" style={{ maxHeight: 260, overflowY: "auto", border: "1px solid var(--line)", borderRadius: "var(--r-md)" }}>
              <table className="tbl--data">
                <thead><tr><th>Matric</th><th>Session</th><th>Sem</th><th>Amount</th><th>For</th><th>Paid on</th></tr></thead>
                <tbody>
                  {preview.slice(0, 200).map((r, i) => (
                    <tr key={i}><td className="tnum">{r.matric}</td><td className="tnum">{r.session}</td><td className="tnum">{r.semester || "—"}</td><td className="tnum">{r.amount || "cleared in full"}</td><td className="sub2">{legacyFeeKind(r) === "GST" ? <b>GST fee</b> : r.purpose || r.note || "School fees"}</td><td className="sub2">{r.paidOn || "—"}</td></tr>
                  ))}
                </tbody>
              </table>
            </div>
            <div className="row mt-3">
              <Btn kind="primary" size="md" disabled={busy || !may} onClick={upload}>{busy ? (progress ?? "Loading…") : `Load ${preview.length.toLocaleString()} rows`}</Btn>
              <Btn kind="ghost" size="md" disabled={busy} onClick={() => setPreview(null)}>Cancel</Btn>
              {busy && progress ? <span className="sub2">{progress}</span> : null}
            </div>
          </PBody>
        </Panel>
      ) : null}

      <Panel title="Start over" right="Delete what this import has loaded, then load it again">
        <PBody>
          <div className="sub2">
            Deletes only payments this screen imported (channel &ldquo;Legacy&rdquo;, reference MOAUM-LEG-…); gateway, bank and Bursary payments are never touched.
            Leave the session blank for everything, or give one (2022/2023).
          </div>
          <div className="row mt-3">
            <input className="ctl" style={{ maxWidth: 160 }} placeholder="All sessions" value={resetSession} onChange={(e) => { setResetSession(e.target.value); setLoaded(null); }} disabled={!may || busy} />
            <Btn kind="ghost" disabled={!may || busy} onClick={() => void checkLoaded()}>Show what is loaded</Btn>
          </div>
          {loaded ? (
            <div className="mt-3">
              <Note kind={loaded.payments ? "bad" : "info"} title={loaded.payments ? `${Number(loaded.payments).toLocaleString()} imported payments for ${Number(loaded.students).toLocaleString()} students` : "Nothing imported to delete"}>
                {loaded.payments ? <>Totalling ₦{Number(loaded.total).toLocaleString()}{loaded.sessions ? ` across ${loaded.sessions}` : ""}. This cannot be undone from the portal.</> : "No old-portal payments are loaded for that selection."}
              </Note>
              {loaded.payments ? (
                <div className="row mt-3">
                  <input className="ctl" style={{ maxWidth: 200 }} placeholder="Type RESET to confirm" value={resetWord} onChange={(e) => setResetWord(e.target.value)} disabled={busy} />
                  <Btn kind="primary" disabled={busy || resetWord !== "RESET"} onClick={() => void resetAll()}>Delete the imported history</Btn>
                </div>
              ) : null}
            </div>
          ) : null}
        </PBody>
      </Panel>
    </>
  );
}
