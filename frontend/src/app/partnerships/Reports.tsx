"use client";
/** V658: the partnership report — one reading of what the office sees, filtered on the server: the totals and summaries on the screen,
 *  the Excel workbook (ten sheets, built on the server), the PDF under the University's header (landscape) */
import { useState } from "react";
import { Btn, Panel, PBody, Spinner, Tiles } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Problem } from "@/lib/api";
import { docSerial, downloadBlob } from "@/lib/exportbrand";
import { esc, printDocument } from "@/lib/document/html";
import { logExport } from "@/lib/export-log";
import { FLAG_WORDS, FUNDING, ORG_TYPES, REPORT_HEAD, STATUS_WORDS, money, reportRows, statusWord, word } from "@/lib/partnerships";
import { PTN, ptnCall, type DeskData } from "./ptn-call";

interface Report {
  totals: Record<string, number>;
  byStatus: { key: string; n: number }[]; byGroup: { key: string; n: number }[]; byCategory: { key: string; grp: string; n: number }[];
  byCountry: { key: string; n: number; active: number }[]; byFaculty: { key: string; n: number; active: number }[];
  byDepartment: { key: string; faculty: string; n: number; active: number }[]; byOrgType: { key: string; n: number }[]; byFunding: { key: string; n: number }[];
  fundingTotals: { key: string; n: number; total: number }[]; byFlag: { key: string; n: number }[];
  rows: Record<string, unknown>[]; agreements: Record<string, unknown>[]; outcomes: { key: string; n: number; quantity: number | null }[];
}
const BLANK = { q: "", status: "", group: "", faculty: "", dept: "", country: "", funding: "", scope: "", compliance: "", orgType: "", from: "", to: "" };

export function Reports({ desk }: { desk: DeskData }) {
  const [f, setF] = useState(BLANK);
  const [r, setR] = useState<Report | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const qs = () => { const p = new URLSearchParams(); for (const [k, v] of Object.entries(f)) if (v) p.set(k, v); return p.toString(); };
  const meta = (): [string, string][] => {
    const m: [string, string][] = [];
    if (f.q) m.push(["Search", f.q]); if (f.status) m.push(["Status", statusWord(f.status)]);
    if (f.group) m.push(["Category group", desk.groups.find((g) => g.code === f.group)?.label ?? f.group]);
    if (f.faculty) m.push(["Faculty", desk.faculties.find((x) => x.code === f.faculty)?.name ?? f.faculty]);
    if (f.dept) m.push(["Department", desk.departments.find((x) => x.code === f.dept)?.name ?? f.dept]);
    if (f.country) m.push(["Country", f.country]); if (f.funding) m.push(["Funding", word(FUNDING, f.funding)]);
    if (f.scope) m.push(["International/local", f.scope === "INTERNATIONAL" ? "International" : "Local"]);
    if (f.compliance) m.push(["Compliance", f.compliance === "REQUIRED" ? "Compliance review required" : FLAG_WORDS[f.compliance] ?? f.compliance]);
    if (f.orgType) m.push(["Organisation type", word(ORG_TYPES, f.orgType)]); if (f.from || f.to) m.push(["Received", `${f.from || "the start"} to ${f.to || "today"}`]);
    return m.length ? m : [["Scope", "All partnerships the office sees"]];
  };

  async function generate() {
    setBusy("gen"); setProblem(null);
    try { const x = await ptnCall<Report>(`/report?${qs()}`); if (x.ok) setR(x.data); else setProblem(x.problem); } finally { setBusy(null); }
  }
  async function excel() {
    setBusy("xlsx"); setProblem(null);
    try {
      const res = await fetch(`${PTN}/report/workbook?${qs()}`, { cache: "no-store" });
      if (!res.ok) { const j = await res.json().catch(() => null); setProblem(j ?? { status: res.status, title: res.statusText }); return; }
      downloadBlob(await res.blob(), `partnership-report-${new Date().toISOString().slice(0, 10)}.xlsx`);
      logExport({ report: "Collaboration & Partnership Report", format: "XLSX", rows: r?.rows.length ?? 0, meta: meta() });
    } finally { setBusy(null); }
  }
  async function pdf() {
    if (!r) return;
    const serial = docSerial("PTN");
    const table = (head: string[], rows: (string | number | null)[][]) =>
      `<table class="t"><thead><tr><th>S/N</th>${head.map((h) => `<th>${esc(h)}</th>`).join("")}</tr></thead><tbody>${rows.map((row, i) => `<tr><td>${i + 1}</td>${row.map((c) => `<td>${esc(c ?? "")}</td>`).join("")}</tr>`).join("")}</tbody></table>`;
    const t = r.totals;
    const body = [
      `<h3>Summary</h3>`, table(["Item", "Count"], [["Total proposals", t.total], ["Approved", t.approved], ["Declined", t.declined], ["Active", t.active], ["Closed", t.closed],
        ["Pending", t.pending], ["Under review", t.under_review], ["International", t.international], ["Compliance review required", t.compliance_review]]),
      `<h3>By status</h3>`, table(["Status", "Proposals"], r.byStatus.map((x) => [statusWord(x.key), x.n])),
      `<h3>By category</h3>`, table(["Category", "Group", "Proposals"], r.byCategory.map((x) => [x.key, x.grp, x.n])),
      `<h3>By country</h3>`, table(["Country", "Proposals", "Active"], r.byCountry.map((x) => [x.key, x.n, x.active])),
      `<h3>By faculty</h3>`, table(["Faculty", "Proposals", "Active"], r.byFaculty.map((x) => [x.key, x.n, x.active])),
      `<h3>By department</h3>`, table(["Department", "Faculty", "Proposals", "Active"], r.byDepartment.map((x) => [x.key, x.faculty, x.n, x.active])),
      `<h3>Funding</h3>`, table(["Funding", "Proposals", "Estimated budget"], [...r.byFunding.map((x) => [word(FUNDING, x.key), x.n, ""] as (string | number)[]),
        ...r.fundingTotals.map((x) => [`Budget stated in ${x.key}`, x.n, money(x.total)] as (string | number)[])]),
      `<h3>Compliance flags (for review)</h3>`, table(["Flag", "Proposals"], r.byFlag.map((x) => [FLAG_WORDS[x.key] ?? x.key, x.n])),
      `<h3>Partnerships</h3>`, table(REPORT_HEAD, reportRows(r.rows)),
      r.agreements.length ? `<h3>Agreements</h3>` + table(["Reference", "Partnership", "Organisation", "Type", "Status", "Expires"],
        r.agreements.map((a) => [String(a.reference), String(a.partnership), String(a.org_name), String(a.agreement_type), String(a.status), String(a.expires_on ?? "")])) : "",
    ].join("");
    logExport({ report: "Collaboration & Partnership Report", format: "PDF", rows: r.rows.length, meta: meta(), serial });
    await printDocument("STANDARD_REPORT", { title: "COLLABORATION & PARTNERSHIP REPORT", meta: meta(), bodyHtml: body, reference: serial, orientation: "landscape" });
  }

  const deps = desk.departments.filter((d) => !f.faculty || d.faculty_code === f.faculty);
  return (
    <div className="stack">
      <Panel title="Partnership report">
        <PBody>
          <div className="grid grid--4">
            <Field id="rp-q" label="Search"><input id="rp-q" className="ctl" value={f.q} onChange={(e) => setF({ ...f, q: e.target.value })} /></Field>
            <Field id="rp-status" label="Status"><select id="rp-status" className="ctl" value={f.status} onChange={(e) => setF({ ...f, status: e.target.value })}><option value="">Any</option>{Object.entries(STATUS_WORDS).filter(([k]) => k !== "DRAFT").map(([k, [l]]) => <option key={k} value={k}>{l}</option>)}</select></Field>
            <Field id="rp-group" label="Category group"><select id="rp-group" className="ctl" value={f.group} onChange={(e) => setF({ ...f, group: e.target.value })}><option value="">Any</option>{desk.groups.map((g) => <option key={g.code} value={g.code}>{g.label}</option>)}</select></Field>
            <Field id="rp-org" label="Organisation type"><select id="rp-org" className="ctl" value={f.orgType} onChange={(e) => setF({ ...f, orgType: e.target.value })}><option value="">Any</option>{ORG_TYPES.map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select></Field>
            <Field id="rp-fac" label="Faculty"><select id="rp-fac" className="ctl" value={f.faculty} onChange={(e) => setF({ ...f, faculty: e.target.value, dept: "" })}><option value="">Any</option>{desk.faculties.map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}</select></Field>
            <Field id="rp-dept" label="Department"><select id="rp-dept" className="ctl" value={f.dept} onChange={(e) => setF({ ...f, dept: e.target.value })}><option value="">Any</option>{deps.map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}</select></Field>
            <Field id="rp-country" label="Country"><input id="rp-country" className="ctl" value={f.country} onChange={(e) => setF({ ...f, country: e.target.value })} /></Field>
            <Field id="rp-fund" label="Funding"><select id="rp-fund" className="ctl" value={f.funding} onChange={(e) => setF({ ...f, funding: e.target.value })}><option value="">Any</option>{FUNDING.map(([k, l]) => <option key={k} value={k}>{l}</option>)}</select></Field>
            <Field id="rp-scope" label="International/local"><select id="rp-scope" className="ctl" value={f.scope} onChange={(e) => setF({ ...f, scope: e.target.value })}><option value="">Either</option><option value="INTERNATIONAL">International</option><option value="LOCAL">Local</option></select></Field>
            <Field id="rp-comp" label="Compliance"><select id="rp-comp" className="ctl" value={f.compliance} onChange={(e) => setF({ ...f, compliance: e.target.value })}><option value="">Any</option><option value="REQUIRED">Compliance review required</option>{Object.entries(FLAG_WORDS).map(([k, l]) => <option key={k} value={k}>Flag: {l}</option>)}</select></Field>
            <Field id="rp-from" label="Received from"><input id="rp-from" type="date" className="ctl" value={f.from} onChange={(e) => setF({ ...f, from: e.target.value })} /></Field>
            <Field id="rp-to" label="Received to"><input id="rp-to" type="date" className="ctl" value={f.to} onChange={(e) => setF({ ...f, to: e.target.value })} /></Field>
          </div>
          <div className="row mt-1" style={{ gap: 8, flexWrap: "wrap" }}>
            <Btn kind="primary" busy={busy === "gen"} busyLabel="Reading…" onClick={() => void generate()}>Generate report</Btn>
            {r && desk.permissions.includes("EXPORT_PARTNERSHIP") ? <>
              <Btn kind="secondary" busy={busy === "xlsx"} busyLabel="Preparing…" onClick={() => void excel()}>Download Excel</Btn>
              <Btn kind="secondary" onClick={() => void pdf()}>Print PDF</Btn>
            </> : null}
          </div>
        </PBody>
      </Panel>
      {problem ? <ProblemNotice problem={problem} /> : null}
      {busy === "gen" && !r ? <div className="row row--tight sub2"><Spinner /> Reading…</div> : null}
      {r ? (
        <>
          <Tiles cls="grid--4" items={[["Total proposals", String(r.totals.total ?? 0), null], ["Approved", String(r.totals.approved ?? 0), null], ["Active", String(r.totals.active ?? 0), "var(--green-ink)"],
            ["Declined", String(r.totals.declined ?? 0), null], ["Closed", String(r.totals.closed ?? 0), null], ["Pending", String(r.totals.pending ?? 0), null],
            ["Under review", String(r.totals.under_review ?? 0), null], ["International", String(r.totals.international ?? 0), null]]} />
          <div className="grid grid--2">
            {([["By status", r.byStatus.map((x) => [statusWord(x.key), x.n])], ["By category group", r.byGroup.map((x) => [x.key, x.n])],
              ["By country", r.byCountry.map((x) => [x.key, x.n])], ["By faculty", r.byFaculty.map((x) => [x.key, x.n])],
              ["By department", r.byDepartment.map((x) => [x.key, x.n])], ["By organisation type", r.byOrgType.map((x) => [word(ORG_TYPES, x.key), x.n])],
              ["Funding", [...r.byFunding.map((x) => [word(FUNDING, x.key), x.n]), ...r.fundingTotals.map((x) => [`Budget in ${x.key}: ${money(x.total)}`, x.n])]],
              ["Compliance flags (for review)", r.byFlag.map((x) => [FLAG_WORDS[x.key] ?? x.key, x.n])]] as [string, (string | number)[][]][]).map(([title, rows]) => (
              <Panel key={title} title={title}>
                <div className="tablewrap" tabIndex={0}><table className="tbl--data"><thead><tr><th>{title.replace(/^By /, "").replace(/^\w/, (c) => c.toUpperCase())}</th><th className="num">Proposals</th></tr></thead>
                  <tbody>{rows.length ? rows.map(([k, n], i) => <tr key={i}><td>{k}</td><td className="num tnum">{n}</td></tr>) : <tr><td colSpan={2} className="sub2">None</td></tr>}</tbody></table></div>
              </Panel>
            ))}
          </div>
          <Panel title="Partnerships" right={<span className="sub2">{r.rows.length} (the first 5,000; every one in the Excel and the PDF)</span>}>
            <div className="tablewrap" tabIndex={0}><table className="tbl--data" style={{ minWidth: 1000 }}>
              <thead><tr><th className="mid">S/N</th>{REPORT_HEAD.map((h) => <th key={h}>{h}</th>)}</tr></thead>
              <tbody>{reportRows(r.rows.slice(0, 200)).map((row, i) => <tr key={i}><td className="mid tnum">{i + 1}</td>{row.map((c, j) => <td key={j} className={j === 0 ? "tnum" : "sub2"}>{c}</td>)}</tr>)}</tbody>
            </table></div>
          </Panel>
        </>
      ) : null}
    </div>
  );
}
