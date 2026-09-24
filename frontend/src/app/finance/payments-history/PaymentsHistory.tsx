"use client";

/** t/paymenthistory — bulk-load past students' payment (school-fees) history (V120). Bursary and ICT. */
import { useState } from "react";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { xlsxRowsAsync, buildXlsx } from "@/lib/xlsx";
import { Btn, Note, Panel, PBody, RoleLine } from "@/components/proto/ui";
import { ProblemNotice } from "@/components/ProblemNotice";

const MAY = ["bursar", "super", "ict", "admin"];
const CHUNK = 400;

type Totals = { imported: number; duplicate: number; no_student: number; bad_amount: number; skipped: number };

export function PaymentsHistory({ actingOffice }: { actingOffice: string | null }) {
  const may = MAY.includes(actingOffice ?? "");
  const [busy, setBusy] = useState(false);
  const [progress, setProgress] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [msg, setMsg] = useState<string | null>(null);

  function downloadTemplate() {
    const blob = buildXlsx(
      ["Matriculation Number", "Session", "Amount", "Purpose", "Payment Date", "Channel", "Reference", "Receipt No"],
      [
        ["MOAUM/CSC/19/1234", "2019/2020", "45000", "School fees", "2019-11-05", "BANK", "RRR-100200300", "RCT-2019-00012"],
        ["MOAUM/CSC/19/1234", "2020/2021", "50000", "School fees", "2020-10-20", "REMITA", "RRR-100200999", ""],
      ],
      "Payment history",
    );
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = "Payment history template.xlsx";
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  }

  async function upload(file: File) {
    setBusy(true); setProblem(null); setMsg(null); setProgress("Reading the spreadsheet…");
    try {
      const grid = await xlsxRowsAsync(await file.arrayBuffer());
      const header = (grid[0] ?? []).map((c) => String(c ?? "").trim().toLowerCase());
      const at = (names: string[]) => header.findIndex((h) => names.some((n) => h.includes(n)));
      const ci = {
        matric: at(["matric", "reg"]), session: at(["session"]), amount: at(["amount"]),
        purpose: at(["purpose", "category", "fee type", "description", "type"]),
        date: at(["date", "paid on"]), channel: at(["channel", "method"]),
        reference: at(["reference", "rrr", "transaction"]), receipt: at(["receipt"]),
      };
      if (ci.matric < 0 || ci.amount < 0) { setProblem({ status: 400, title: "That file needs at least Matriculation Number and Amount columns.", detail: "Download the template for the full set of columns." }); return; }
      const g = (r: (string | number | null)[], i: number) => (i >= 0 ? String(r[i] ?? "").trim() : "");
      const rows = grid.slice(1)
        .filter((r) => g(r, ci.matric) && !/^matric/i.test(g(r, ci.matric)))
        .map((r) => ({
          matric: g(r, ci.matric), session: g(r, ci.session), amount: g(r, ci.amount), purpose: g(r, ci.purpose),
          date: g(r, ci.date), channel: g(r, ci.channel), reference: g(r, ci.reference), receipt: g(r, ci.receipt),
        }));
      if (!rows.length) { setProblem({ status: 400, title: "No payment rows were found in the file." }); return; }

      const totals: Totals = { imported: 0, duplicate: 0, no_student: 0, bad_amount: 0, skipped: 0 };
      let firstErr: string | null = null;
      for (let i = 0; i < rows.length; i += CHUNK) {
        const batch = rows.slice(i, i + CHUNK);
        setProgress(`Loading ${Math.min(i + batch.length, rows.length).toLocaleString()} of ${rows.length.toLocaleString()} payments…`);
        const res = await fetch("/api/bff/api/v1/finance/payments/import", {
          method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader("Past students' payment history loaded") },
          body: JSON.stringify({ rows: batch }),
        });
        const j = await res.json().catch(() => null);
        if (!res.ok) {
          const base = (j ?? { status: res.status, title: res.statusText }) as Problem;
          setProblem({ ...base, detail: `${base.detail ? base.detail + " " : ""}${totals.imported} payments were loaded before this batch was refused. The import is idempotent — fix and upload again.` });
          return;
        }
        const c = (j ?? {}) as Partial<Totals> & { first_error?: string | null };
        totals.imported += Number(c.imported ?? 0); totals.duplicate += Number(c.duplicate ?? 0);
        totals.no_student += Number(c.no_student ?? 0); totals.bad_amount += Number(c.bad_amount ?? 0);
        totals.skipped += Number(c.skipped ?? 0);
        if (!firstErr && c.first_error) firstErr = c.first_error;
      }
      setProgress(null);
      setMsg(`${totals.imported.toLocaleString()} payments loaded`
        + (totals.duplicate ? ` · ${totals.duplicate.toLocaleString()} already on record (skipped)` : "")
        + (totals.no_student ? ` · ${totals.no_student.toLocaleString()} matched no student` : "")
        + (totals.bad_amount ? ` · ${totals.bad_amount.toLocaleString()} had no valid amount` : "")
        + (totals.skipped ? ` · ${totals.skipped.toLocaleString()} skipped by an error (first: ${firstErr ?? "no detail"})` : "")
        + ".");
    } catch {
      setProblem({ status: 400, title: "That file could not be read as a spreadsheet." });
    } finally {
      setBusy(false); setProgress(null);
    }
  }

  return (
    <>
      <RoleLine allowed={["bursar"]} actingOffice={actingOffice} canAct={may} action="Loading past payment history" />
      <Note kind="info" title="Load past students' payment history">
        This carries confirmed school-fees payments over from the old portal, exactly as they were — the original
        reference, receipt, amount, date and channel are kept. It is <b>not</b> for new payments (those are confirmed on
        the reconciliation desk). A payment already on record is left alone, so a file may be uploaded again safely, and
        no student is notified. Each payment is matched to a student by matriculation, admission or JAMB number.
      </Note>
      {!may ? <Note kind="bad" title="This desk is for the Bursary and the Directorate of ICT">Your office may not load payment history.</Note> : null}
      {problem ? <ProblemNotice problem={problem} /> : null}
      {msg ? <Note kind="ok" title="Payment history loaded">{msg}</Note> : null}

      <Panel title="The payment-history file" right="School fees">
        <PBody>
          <div className="row">
            <Btn kind="ghost" onClick={downloadTemplate}>Download template</Btn>
            <label className={`btn btn--primary m-0${!may || busy ? " btn--disabled" : ""}`} style={{ cursor: may && !busy ? "pointer" : "not-allowed", opacity: !may ? 0.6 : 1 }}>
              {busy ? (progress ?? "Loading…") : "Choose the payment-history file (.xlsx)"}
              <input type="file" accept=".xlsx" style={{ display: "none" }} disabled={!may || busy} onChange={(e) => { const f = e.target.files?.[0]; if (f) void upload(f); e.target.value = ""; }} />
            </label>
            {busy && progress ? <span className="sub2">{progress}</span> : null}
          </div>
          <div className="sub2 mt-2">
            <b>Amount</b> may carry a currency sign or commas — only the number is read. <b>Session</b> is like 2019/2020;
            a blank session is filed under <b>LEGACY</b>. <b>Payment Date</b> like 2019-11-05; a blank date defaults to
            today. A row with no <b>Reference</b> is given a stable one derived from the row, so re-uploading the same
            file never duplicates. Large files are loaded in batches of {CHUNK}.
          </div>
        </PBody>
      </Panel>
    </>
  );
}
