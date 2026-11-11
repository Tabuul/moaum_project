"use client";

/**
 * V654: the historical fee reports — by period (every graduate's session and semester: assessed, paid, outstanding, the source and
 * the statuses) and the graduates' financial clearance (one row per graduate) — filtered on the server, to Excel (S/N first, numbers
 * as text) and PDF (the official header, the filters, the totals, continuous S/N) with the University's exports.
 */
import { useState } from "react";
import { Btn, Note, Panel, PBody, Spinner, Tiles } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify } from "@/components/proto/Toast";
import type { Problem } from "@/lib/api";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { CLEARANCE_HEAD, clearanceRows, FINANCIAL_WORDS, naira, num, PERIOD_WORDS, REPORT_HEAD, reportRows, can, type ClearanceRow, type Desk, type FinancialStatus, type PeriodStatus, type ReportRow } from "@/lib/historical-fees";
import { hfCall } from "./hf-call";

export function Reports({ desk, faculties, programmes }: { desk: Desk; faculties: { code: string; name: string }[]; programmes: { code: string; name: string; faculty_code: string }[] }) {
  const [kind, setKind] = useState<"periods" | "clearance">("periods");
  const [f, setF] = useState({ session: "", semester: "", level: "", faculty: "", programme: "", status: "", financial: "", graduation: "", source: "", scope: "", type: "" });
  const [rows, setRows] = useState<ReportRow[] | null>(null);
  const [crows, setCrows] = useState<ClearanceRow[] | null>(null);
  const [capped, setCapped] = useState(false);
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);

  async function read() {
    setBusy(true);
    setProblem(null);
    const qs = new URLSearchParams();
    for (const [k, v] of Object.entries(f)) if (v) qs.set(k, v);
    if (kind === "periods") {
      const r = await hfCall<{ students: number; rows: ReportRow[]; capped: boolean }>(`/report?${qs}`);
      if (r.ok) { setRows(r.data.rows); setCapped(r.data.capped); } else setProblem(r.problem);
    } else {
      const r = await hfCall<ClearanceRow[]>(`/clearance-report?${qs}`);
      if (r.ok) setCrows(r.data); else setProblem(r.problem);
    }
    setBusy(false);
  }

  const meta = (): [string, string][] => [
    ["Session", f.session || "All"], ["Semester", f.semester ? ["", "First", "Second", "Third"][Number(f.semester)] : "All"], ["Level", f.level || "All"],
    ["Faculty", faculties.find((x) => x.code === f.faculty)?.name ?? "All"], ["Programme", programmes.find((x) => x.code === f.programme)?.name ?? "All"],
    ["Period status", f.status ? PERIOD_WORDS[f.status as PeriodStatus]?.[0] ?? f.status : "All"],
    ["Financial status", f.financial ? FINANCIAL_WORDS[f.financial as FinancialStatus]?.[0] ?? f.financial : "All"], ["Graduation session", f.graduation || "All"],
    ["Standing", f.scope === "ALL" ? "Everyone" : f.scope === "ACTIVE" ? "Students still studying" : "Graduates"], ["Programme type", f.type === "PG" ? "Postgraduate" : f.type === "UG" ? "Undergraduate" : "All"],
  ];

  async function exportAs(format: "XLSX" | "PDF") {
    const serial = docSerial("HFR");
    if (kind === "periods" && rows) {
      const title = "Historical fee assessment report";
      const t = rows.reduce((a, r) => ({ assessed: a.assessed + num(r.assessed), paid: a.paid + num(r.paid), outstanding: a.outstanding + num(r.outstanding) }), { assessed: 0, paid: 0, outstanding: 0 });
      const m = meta().concat([["Rows", rows.length.toLocaleString()], ["Totals", `assessed ${naira(t.assessed)} · paid ${naira(t.paid)} · outstanding ${naira(t.outstanding)}`]]);
      if (format === "XLSX") downloadBlob(await brandedXlsx(title, REPORT_HEAD, reportRows(rows), { sheetName: "Historical fees", serial, meta: m }), `historical-fees-${new Date().toISOString().slice(0, 10)}.xlsx`);
      else brandedPrint(title, "Graduates' school fees by session and semester: assessed at the fees of the period, paid, outstanding", REPORT_HEAD, reportRows(rows), serial, { meta: m, orientation: "landscape" });
    } else if (kind === "clearance" && crows) {
      const title = "Graduated student financial clearance report";
      const m = meta().concat([["Graduates", crows.length.toLocaleString()]]);
      if (format === "XLSX") downloadBlob(await brandedXlsx(title, CLEARANCE_HEAD, clearanceRows(crows), { sheetName: "Financial clearance", serial, meta: m }), `financial-clearance-${new Date().toISOString().slice(0, 10)}.xlsx`);
      else brandedPrint(title, "Each graduate's historical school fees and the Bursary's clearance", CLEARANCE_HEAD, clearanceRows(crows), serial, { meta: m, orientation: "landscape" });
    }
    notify("Report exported");
  }

  const t = rows?.reduce((a, r) => ({ assessed: a.assessed + num(r.assessed), paid: a.paid + num(r.paid), outstanding: a.outstanding + num(r.outstanding),
    review: a.review + (r.status === "REQUIRES_REVIEW" ? 1 : 0), cleared: a.cleared + (r.status === "CLEARED" ? 1 : 0), partial: a.partial + (r.status === "PARTIALLY_PAID" ? 1 : 0) }),
    { assessed: 0, paid: 0, outstanding: 0, review: 0, cleared: 0, partial: 0 });
  const mayExport = can(desk, "EXPORT_HISTORICAL_FEE_REPORT");
  const has = kind === "periods" ? !!rows?.length : !!crows?.length;

  return (
    <Panel title="Historical fee reports" right={has && mayExport ? <span className="row row--tight"><Btn kind="secondary" onClick={() => exportAs("XLSX")}>Excel</Btn><Btn kind="secondary" onClick={() => exportAs("PDF")}>PDF / print</Btn></span> : undefined}>
      <PBody>
        <div className="row row--end" style={{ flexWrap: "wrap" }}>
          <Field id="r-kind" label="Report"><select id="r-kind" className="ctl" value={kind} onChange={(e) => setKind(e.target.value as "periods" | "clearance")}>
            <option value="periods">Historical fees by session and semester</option><option value="clearance">Graduates&rsquo; financial clearance</option></select></Field>
          {kind === "periods" ? (
            <>
              <Field id="r-ses" label="Session"><select id="r-ses" className="ctl" value={f.session} onChange={(e) => setF({ ...f, session: e.target.value })}><option value="">All</option>{desk.sessions.map((x) => <option key={x} value={x}>{x}</option>)}</select></Field>
              <Field id="r-sem" label="Semester"><select id="r-sem" className="ctl" value={f.semester} onChange={(e) => setF({ ...f, semester: e.target.value })}><option value="">All</option><option value="1">First</option><option value="2">Second</option><option value="3">Third</option></select></Field>
              <Field id="r-lvl" label="Level"><select id="r-lvl" className="ctl" value={f.level} onChange={(e) => setF({ ...f, level: e.target.value })}><option value="">All</option>{[100, 200, 300, 400, 500, 600, 700, 800, 900].map((l) => <option key={l} value={l}>{l}</option>)}</select></Field>
              <Field id="r-st" label="Period status"><select id="r-st" className="ctl" value={f.status} onChange={(e) => setF({ ...f, status: e.target.value })}><option value="">All</option>{(["CLEARED", "PARTIALLY_PAID", "OUTSTANDING", "CREDIT", "REQUIRES_REVIEW", "PENDING_APPROVAL"] as PeriodStatus[]).map((k) => <option key={k} value={k}>{PERIOD_WORDS[k][0]}</option>)}</select></Field>
              <Field id="r-src" label="Assessment source"><select id="r-src" className="ctl" value={f.source} onChange={(e) => setF({ ...f, source: e.target.value })}><option value="">All</option><option value="STRUCTURE">Fee structure</option><option value="ASSESSMENT">Approved assessment</option><option value="NONE">None (requires review)</option></select></Field>
            </>
          ) : null}
          <Field id="r-scope" label="Standing"><select id="r-scope" className="ctl" value={f.scope} onChange={(e) => setF({ ...f, scope: e.target.value })}><option value="">Graduates</option><option value="ACTIVE">Students still studying</option><option value="ALL">Everyone</option></select></Field>
          <Field id="r-type" label="Programme type"><select id="r-type" className="ctl" value={f.type} onChange={(e) => setF({ ...f, type: e.target.value })}><option value="">All</option><option value="UG">Undergraduate</option><option value="PG">Postgraduate</option></select></Field>
          <Field id="r-fac" label="Faculty"><select id="r-fac" className="ctl" value={f.faculty} onChange={(e) => setF({ ...f, faculty: e.target.value, programme: "" })}><option value="">All</option>{faculties.map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}</select></Field>
          <Field id="r-prog" label="Programme"><select id="r-prog" className="ctl" value={f.programme} onChange={(e) => setF({ ...f, programme: e.target.value })}><option value="">All</option>{programmes.filter((x) => !f.faculty || x.faculty_code === f.faculty).map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}</select></Field>
          <Field id="r-fin" label="Financial status"><select id="r-fin" className="ctl" value={f.financial} onChange={(e) => setF({ ...f, financial: e.target.value })}><option value="">All</option>{(Object.keys(FINANCIAL_WORDS) as FinancialStatus[]).map((k) => <option key={k} value={k}>{FINANCIAL_WORDS[k][0]}</option>)}</select></Field>
          <Field id="r-grad" label="Graduation session"><select id="r-grad" className="ctl" value={f.graduation} onChange={(e) => setF({ ...f, graduation: e.target.value })}><option value="">All</option>{desk.sessions.map((x) => <option key={x} value={x}>{x}</option>)}</select></Field>
          <Btn kind="primary" disabled={busy} busyLabel="Reading…" onClick={read}>Read the report</Btn>
        </div>
        {busy ? <div className="row row--tight sub2 mt-2"><Spinner /> Reading…</div> : null}
        {problem ? <ProblemNotice problem={problem} /> : null}
        {kind === "periods" && rows && t ? (
          <>
            {capped ? <Note kind="info" title="The first 3,000 graduates in the scope">Narrow the scope (a faculty, a programme, a graduation session) for the rest.</Note> : null}
            <Tiles items={[
              ["Periods", rows.length.toLocaleString(), null, `${new Set(rows.map((r) => r.matric_no)).size.toLocaleString()} students`],
              ["Total assessed", naira(t.assessed), null, `${t.cleared.toLocaleString()} cleared · ${t.partial.toLocaleString()} partly paid`],
              ["Total paid", naira(t.paid), "var(--green-ink)", "Confirmed school-fee payments"],
              ["Total outstanding", naira(t.outstanding), t.outstanding > 0 ? "var(--red-ink)" : null, `${t.review.toLocaleString()} period(s) require review`],
            ]} />
          </>
        ) : null}
        {kind === "clearance" && crows ? (
          <Tiles items={[
            ["Graduates", crows.length.toLocaleString(), null, "In the scope"],
            ["Outstanding", crows.filter((r) => num(r.outstanding) > 0).length.toLocaleString(), "var(--red-ink)", naira(crows.reduce((n, r) => n + num(r.outstanding), 0))],
            ["Financially cleared", crows.filter((r) => r.financial_status === "FINANCIALLY_CLEARED").length.toLocaleString(), "var(--green-ink)", "Nothing owed or to assess"],
            ["Bursary stage cleared", crows.filter((r) => r.bursary_clearance === "CLEARED").length.toLocaleString(), null, "On the final clearance"],
          ]} />
        ) : null}
        {has ? <div className="sub2 mt-2">The rows are in the export; the Students tab opens each graduate.</div> : rows || crows ? <div className="sub2 mt-2">Nothing in the scope.</div> : null}
      </PBody>
    </Panel>
  );
}
