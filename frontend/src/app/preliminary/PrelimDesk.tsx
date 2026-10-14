"use client";

/**
 * The Preliminary Science desk (V446). The figures for the session, each a filter of the list behind it; the applications,
 * searched, filtered, sorted and paged on the server (S/N counts on across pages and is display only); the list exported as one of
 * the programme's reports (Excel, or PDF on the University's letterhead), its S/N from 1 for the filter exported; each
 * application opened for review. The Academic Office publishes the decided applications. What any office may do is the
 * server's to decide — the buttons here only follow it.
 */
import { useState } from "react";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { SearchSelect } from "@/components/proto/SearchSelect";
import { useQueryNav } from "@/lib/query-nav";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { ELIGIBILITY, REMEDIATION, STATE, VERIFICATION, labelOf, naira, pcall, when, type PrelimRow } from "@/lib/preliminary";
import { PrelimDetail } from "./PrelimDetail";

export interface DeskFilters {
  session: string; view: string; q: string; target: string; sittings: string; eligibility: string; remediation: string; state: string; paid: string;
  sex: string; origin: string; lga: string; from: string; to: string; sort: string; size: string;
}
export interface PrelimStats {
  total: number; paid: number; submitted: number; incomplete: number; pendingReview: number; underReview: number; correction: number; eligible: number;
  notEligible: number; remediationRequired: number; admitted: number; notAdmitted: number; withdrawn: number;
  byTarget: { programmeCode: string; name: string; n: number }[]; bySittings: { sittings: number; n: number }[];
}
export interface PrelimSummary {
  session: string; routeSession: string; sessions: string[]; scope: { office: string; department: string; faculty: string; scoped: boolean };
  stats: PrelimStats; window: { state: string; opens_at: string | null; closes_at: string | null };
  fee: { stated: boolean; application_fee: number | null; portal_charge: number | null } | null; missingTargets: number; toPublish: number;
  may: { review: boolean; decide: boolean; recommend: boolean; configure: boolean; fees: boolean };
}

const TILES: [keyof PrelimStats, string, string][] = [
  ["total", "Total applications", "every application started"], ["paid", "Paid", "application fee verified"], ["submitted", "Submitted", "submitted, not withdrawn"],
  ["incomplete", "Incomplete", "started, not yet submitted"], ["pendingReview", "Pending review", "submitted, not yet taken up"], ["underReview", "Under review", "taken up, no outcome published"],
  ["eligible", "Eligible", "meets the entry requirement"], ["notEligible", "Not eligible", "below it, or no released result"], ["remediationRequired", "Remediation required", "to make up before completion"],
  ["admitted", "Admitted", "published"], ["notAdmitted", "Not admitted", "published"], ["withdrawn", "Withdrawn", "by the applicant"],
];
/** the programme's reports: each the list under a filter, exported */
const REPORTS: [string, string, Partial<DeskFilters>][] = [
  ["Preliminary Science application report", "Every application of the session", {}],
  ["Preliminary Science admission report", "The admitted applicants", { view: "admitted" }],
  ["O'Level eligibility report", "The submitted applications and how each stands against the entry requirement", { view: "submitted" }],
  ["Remediation required report", "The applicants with O'Level credits to make up before completion", { view: "remediationRequired" }],
  ["Application status report", "Every application and its state", { sort: "number" }],
];
const HEAD = ["S/N", "Application no", "Name", "Sex", "Target programme", "Credits", "Core credits", "Sittings", "Eligibility", "Remediation", "O'Level", "Paid", "Status", "Submitted", "State of origin", "LGA"];

export function PrelimDesk({ summary, list, filters, page, generatedBy }: {
  summary: PrelimSummary; list: { session: string; total: number; page: number; size: number; rows: PrelimRow[] }; filters: DeskFilters; page: number; generatedBy: string | null;
}) {
  const go = useQueryNav();
  const [f, setF] = useState<DeskFilters>(filters);
  const [open, setOpen] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const s = summary.stats;
  const size = Number(filters.size || 50);
  const pages = Math.max(1, Math.ceil(list.total / size));
  const href = (patch: Partial<DeskFilters>, pg = 1) => {
    const n = { ...filters, ...patch };
    const qs = new URLSearchParams();
    (Object.keys(n) as (keyof DeskFilters)[]).forEach((k) => { if (n[k]) qs.set(k, n[k]); });
    if (pg > 1) qs.set("page", String(pg));
    return `/preliminary?${qs.toString()}`;
  };
  const statusWord = (r: PrelimRow) => r.state === "NOT_ADMITTED" || r.state === "REJECTED" ? `${labelOf(STATE, r.state)[0]}${r.published_at ? "" : " (not published)"}` : labelOf(STATE, r.state)[0];
  const cells = (r: PrelimRow, i: number) => [i, r.application_no, `${r.surname}, ${r.other_names}`, r.sex ?? "", r.target_name ?? "", r.total_credits ?? "", r.core_credits ?? "", r.sittings ?? "",
    labelOf(ELIGIBILITY, r.eligibility_status)[0], r.remediation_status ? labelOf(REMEDIATION, r.remediation_status)[0] : "", labelOf(VERIFICATION, r.olevel_verification)[0],
    r.paid ? "Yes" : "No", statusWord(r), r.submitted_at ? r.submitted_at.slice(0, 10) : "", r.state_of_origin ?? "", r.lga ?? ""];
  const meta = (title: string): [string, string][] => [["Session", list.session], ["Filter", title], ...(summary.scope.scoped ? [["Scope", summary.scope.department || summary.scope.faculty] as [string, string]] : []),
    ...(Object.entries(filters).filter(([k, v]) => v && !["session", "size", "sort"].includes(k)).map(([k, v]) => [k, v] as [string, string]))];
  async function exportRows(patch: Partial<DeskFilters>) {
    const n = { ...filters, ...patch };
    const qs = new URLSearchParams();
    (Object.keys(n) as (keyof DeskFilters)[]).forEach((k) => { if (n[k] && k !== "size") qs.set(k, n[k]); });
    qs.set("size", "5000"); qs.set("page", "0");
    const r = await pcall<{ rows: PrelimRow[] }>(`/api/v1/admissions/preliminary/applications?${qs.toString()}`);
    if (!r.ok) { notifyProblem(r.problem); return null; }
    return r.data.rows.map((row, i) => cells(row, i + 1));
  }
  async function excel(title: string, patch: Partial<DeskFilters>) {
    const rows = await exportRows(patch);
    if (rows) downloadBlob(await brandedXlsx(title, HEAD, rows, { sheetName: "Applications", serial: docSerial("PRESCI"), meta: meta(title) }), `${title.toLowerCase().replace(/[^a-z0-9]+/g, "-")}.xlsx`);
  }
  async function pdf(title: string, sub: string, patch: Partial<DeskFilters>) {
    const rows = await exportRows(patch);
    if (rows) brandedPrint(title, sub, HEAD, rows, docSerial("PRESCI"), { meta: meta(title), generatedBy, orientation: "landscape" });
  }
  async function publish() {
    if (!window.confirm(`Publish the ${summary.toPublish} decided application${summary.toPublish === 1 ? "" : "s"} of ${list.session}? Each applicant is told, and a published outcome stands.`)) return;
    setBusy(true);
    try {
      const r = await pcall<{ admitted: number; not_admitted: number; rejected: number }>("/api/v1/admissions/preliminary/publish", "POST", { session: list.session }, `Preliminary Science outcomes published for ${list.session}`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      notify(`${r.data.admitted} admitted, ${r.data.not_admitted + r.data.rejected} not admitted — published`);
      go(href({}));
    } finally { setBusy(false); }
  }

  return (
    <>
      <PageHead title="Preliminary Science" description={`${list.session} · applications, eligibility, remediation and admission${summary.scope.scoped ? ` · your targets only (${summary.scope.department || summary.scope.faculty})` : ""}`}
        actions={<>
          {summary.may.configure || summary.may.fees ? <LinkBtn href="/preliminary/config">Programme settings</LinkBtn> : null}
          <LinkBtn href="/preliminary/reports">Reports</LinkBtn>
          {summary.may.decide && summary.toPublish > 0 ? <Btn kind="primary" disabled={busy} onClick={() => void publish()}>{busy ? "Publishing…" : `Publish ${summary.toPublish} outcome${summary.toPublish === 1 ? "" : "s"}`}</Btn> : null}
        </>} />
      <div className="row row--inline row--tight mb-2" style={{ flexWrap: "wrap" }}>
        <Pil kind={summary.window.state === "OPEN" ? "ok" : "grey"}>{`Applications ${summary.window.state.toLowerCase()}`}</Pil>
        {summary.window.opens_at ? <span className="sub2">opened {when(summary.window.opens_at)}{summary.window.closes_at ? ` · closes ${when(summary.window.closes_at)}` : " · no closing date set"}</span> : null}
        <span className="sub2">· application fee {summary.fee?.stated && summary.fee.application_fee != null ? naira(Number(summary.fee.application_fee) + Number(summary.fee.portal_charge ?? 0)) : "not configured"}</span>
        {summary.missingTargets ? <Pil kind="warn">{`${summary.missingTargets} target programme${summary.missingTargets === 1 ? "" : "s"} missing from the register`}</Pil> : null}
      </div>
      <Tiles items={TILES.map(([k, label, sub]) => [
        <button key={k} type="button" className="lnk" aria-pressed={filters.view === k} style={{ font: "inherit", padding: 0, background: "none", border: 0, cursor: "pointer", color: "inherit", fontWeight: filters.view === k ? 800 : undefined }}
          onClick={() => go(href({ view: filters.view === k ? "" : k }))}>{label}{filters.view === k ? " ✓" : ""}</button>,
        String(s[k] ?? 0), null, sub] as [React.ReactNode, React.ReactNode, string | null, string])} />

      <Panel title="Applications" right={<span className="row row--inline row--tight">
        <select className="ctl" aria-label="Report" id="ps-report" defaultValue="0">{REPORTS.map((r, i) => <option key={i} value={i}>{r[0]}</option>)}</select>
        <Btn kind="ghost" size="sm" onClick={() => { const r = REPORTS[Number((document.getElementById("ps-report") as HTMLSelectElement).value)]; void excel(r[0], r[2]); }}>Excel</Btn>
        <Btn kind="ghost" size="sm" onClick={() => { const r = REPORTS[Number((document.getElementById("ps-report") as HTMLSelectElement).value)]; void pdf(r[0], r[1], r[2]); }}>PDF</Btn>
      </span>}>
        <PBody>
          <div className="grid grid--4">
            <Field id="pf-q" label="Search"><input id="pf-q" className="ctl" placeholder="Name, number, email or phone" value={f.q} onChange={(e) => setF({ ...f, q: e.target.value })} onKeyDown={(e) => { if (e.key === "Enter") go(href({ q: f.q })); }} /></Field>
            <Field id="pf-t" label="Target programme"><SearchSelect id="pf-t" value={f.target} allLabel="All target programmes" onChange={(v) => go(href({ target: v }))}
              options={s.byTarget.map((t) => ({ value: t.programmeCode, label: t.name, sub: `${t.n} application${t.n === 1 ? "" : "s"}` }))} /></Field>
            <Field id="pf-e" label="Eligibility"><SearchSelect id="pf-e" value={f.eligibility} allLabel="Any eligibility" onChange={(v) => go(href({ eligibility: v }))}
              options={Object.entries(ELIGIBILITY).map(([k, [l]]) => ({ value: k, label: l }))} /></Field>
            <Field id="pf-r" label="Remediation"><SearchSelect id="pf-r" value={f.remediation} allLabel="Any remediation" onChange={(v) => go(href({ remediation: v }))}
              options={Object.entries(REMEDIATION).map(([k, [l]]) => ({ value: k, label: l }))} /></Field>
            <Field id="pf-s" label="Status"><SearchSelect id="pf-s" value={f.state} allLabel="Any status" onChange={(v) => go(href({ state: v }))}
              options={Object.entries(STATE).map(([k, [l]]) => ({ value: k, label: l }))} /></Field>
            <Field id="pf-p" label="Payment"><select id="pf-p" className="ctl" value={f.paid} onChange={(e) => go(href({ paid: e.target.value }))}><option value="">Paid or not</option><option value="true">Paid</option><option value="false">Not paid</option></select></Field>
            <Field id="pf-x" label="Sex"><select id="pf-x" className="ctl" value={f.sex} onChange={(e) => go(href({ sex: e.target.value }))}><option value="">Both</option><option value="F">Female</option><option value="M">Male</option></select></Field>
            <Field id="pf-g" label="O'Level sittings"><select id="pf-g" className="ctl" value={f.sittings} onChange={(e) => go(href({ sittings: e.target.value }))}><option value="">Any</option><option value="1">One</option><option value="2">Two</option><option value="0">None given</option></select></Field>
            <Field id="pf-o" label="State of origin"><input id="pf-o" className="ctl" value={f.origin} onChange={(e) => setF({ ...f, origin: e.target.value })} onBlur={() => f.origin !== filters.origin && go(href({ origin: f.origin }))} /></Field>
            <Field id="pf-l" label="LGA"><input id="pf-l" className="ctl" value={f.lga} onChange={(e) => setF({ ...f, lga: e.target.value })} onBlur={() => f.lga !== filters.lga && go(href({ lga: f.lga }))} /></Field>
            <Field id="pf-from" label="Submitted from"><input id="pf-from" type="date" className="ctl" value={f.from} onChange={(e) => go(href({ from: e.target.value }))} /></Field>
            <Field id="pf-to" label="Submitted to"><input id="pf-to" type="date" className="ctl" value={f.to} onChange={(e) => go(href({ to: e.target.value }))} /></Field>
          </div>
          <div className="row row--inline row--tight mt-2" style={{ flexWrap: "wrap" }}>
            <Field id="pf-sess" label="Session"><select id="pf-sess" className="ctl" value={filters.session || summary.session} onChange={(e) => go(href({ session: e.target.value }))}>{summary.sessions.map((x) => <option key={x} value={x}>{x}</option>)}</select></Field>
            <Field id="pf-sort" label="Sort"><select id="pf-sort" className="ctl" value={filters.sort || "number"} onChange={(e) => go(href({ sort: e.target.value }))}>
              <option value="number">Application number</option><option value="name">Name</option><option value="submitted">Latest submitted</option><option value="credits">Most credits</option><option value="target">Target programme</option></select></Field>
            <Btn kind="ghost" size="sm" onClick={() => go("/preliminary")}>Clear the filters</Btn>
            <span className="sub2">{list.total} application{list.total === 1 ? "" : "s"}</span>
          </div>
          {list.rows.length === 0 ? <Note kind="info" title="No application answers these filters" /> : (
            <DTable noPrint pageSize={0} cols={["S/N|num", "Application no", "Applicant", "Target programme", "Credits|num", "Core|num", "Sittings|num", "Eligibility", "Remediation", "Payment", "Status", "Submitted", ""]}
              rows={list.rows.map((r, i) => [
                (page - 1) * size + i + 1, <span key="n" className="tnum">{r.application_no}</span>,
                <span key="a"><b>{r.surname}</b>, {r.other_names}<div className="sub2">{r.sex === "F" ? "Female" : r.sex === "M" ? "Male" : ""}{r.state_of_origin ? ` · ${r.state_of_origin}` : ""}</div></span>,
                r.target_name ?? <span key="t" className="sub2">not chosen</span>,
                r.total_credits ?? "—", r.core_credits ?? "—", r.sittings ?? 0,
                <Pil key="e" kind={labelOf(ELIGIBILITY, r.eligibility_status)[1] as "ok"}>{labelOf(ELIGIBILITY, r.eligibility_status)[0]}</Pil>,
                r.remediation_status ? <Pil key="r" kind={labelOf(REMEDIATION, r.remediation_status)[1] as "ok"}>{labelOf(REMEDIATION, r.remediation_status)[0]}</Pil> : "—",
                r.paid ? <Pil key="p" kind="ok">Paid</Pil> : <Pil key="p" kind="grey">Not paid</Pil>,
                <span key="s">{statusWord(r)}</span>,
                r.submitted_at ? when(r.submitted_at) : "—",
                <span key="x" className="row row--inline row--tight"><Btn kind="secondary" size="sm" onClick={() => setOpen(r.id)}>Open</Btn>
                  <a className="btn btn--ghost btn--sm" href={`/applicant/preliminary/pdf/form?id=${r.id}`} target="_blank" rel="noopener">Print</a></span>,
              ])} />
          )}
          {pages > 1 ? (
            <div className="row row--inline row--tight mt-2">
              <Btn kind="ghost" size="sm" disabled={page <= 1} onClick={() => go(href({}, page - 1))}>Previous</Btn>
              <span className="sub2">Page {page} of {pages}</span>
              <Btn kind="ghost" size="sm" disabled={page >= pages} onClick={() => go(href({}, page + 1))}>Next</Btn>
            </div>
          ) : null}
        </PBody>
      </Panel>
      {open ? <PrelimDetail id={open} may={summary.may} onClose={(changed) => { setOpen(null); if (changed) go(href({}, page)); }} /> : null}
    </>
  );
}
