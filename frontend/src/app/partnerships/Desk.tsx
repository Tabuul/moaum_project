"use client";
/**
 * V658: Collaboration & Partnerships — the dashboard's figures (each opening its list), the proposals the acting office sees
 * (filtered and paged on the server: the database holds each office to what it may see), the reports and the settings.
 */
import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Btn, PageHead, Panel, PBody, Pil, Spinner, Tabs, Tiles } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Problem } from "@/lib/api";
import { FLAG_WORDS, FUNDING, STATUS_WORDS, dateWords, statusWord } from "@/lib/partnerships";
import { can, ptnCall, type DeskData } from "./ptn-call";
import { Reports } from "./Reports";
import { Settings } from "./Settings";
import { RecordProposal } from "./RecordProposal";

type Tab = "dashboard" | "proposals" | "reports" | "settings";
interface Row {
  id: string; reference: string; org_name: string; country: string | null; category_label: string | null; title: string; faculty: string | null;
  department: string | null; status: string; owner_name: string | null; received_at: string; updated_at: string; next_action: string | null;
  due_on: string | null; overdue: boolean; compliance_review: boolean; flags: string[] | null;
}
const VIEWS: [string, string][] = [["ALL", "All proposals"], ["MINE", "My assignments"], ["REVIEWS", "Reviews asked of my office"], ["PENDING", "Pending review"],
  ["AWAITING", "Awaiting information"], ["DUE_DILIGENCE", "Due diligence"], ["APPROVAL", "Pending approval"], ["AGREEMENTS", "Agreements"],
  ["ACTIVE", "Active partnerships"], ["EXPIRING", "Expiring agreements"], ["OVERDUE", "Overdue"], ["UNASSIGNED", "Unassigned"], ["COMPLIANCE", "Compliance review"]];
const BLANK = { q: "", status: "", group: "", category: "", faculty: "", dept: "", country: "", funding: "", scope: "", compliance: "", owner: "", desk: "", from: "", to: "" };

export function Desk({ desk, initialTab, initialView }: { desk: DeskData; initialTab: Tab; initialView: string | null }) {
  const router = useRouter();
  const reviewerOnly = !can(desk, "VIEW_ALL_PARTNERSHIPS");
  const [tab, setTab] = useState<Tab>(initialTab);
  const [view, setView] = useState(initialView ?? (reviewerOnly ? "REVIEWS" : "ALL"));
  const [f, setF] = useState(BLANK);
  const [page, setPage] = useState(0);
  const [list, setList] = useState<{ rows: Row[]; total: number; size: number } | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [recording, setRecording] = useState(false);

  const load = useCallback(async () => {
    setList(null); setProblem(null);
    const qs = new URLSearchParams({ view, page: String(page), size: "25" });
    for (const [k, v] of Object.entries(f)) if (v) qs.set(k, v);
    const r = await ptnCall<{ rows: Row[]; total: number; size: number }>(`?${qs}`);
    if (r.ok) setList(r.data); else setProblem(r.problem);
  }, [view, page, f]);
  useEffect(() => { if (tab === "proposals") { const t = window.setTimeout(() => void load(), 250); return () => window.clearTimeout(t); } }, [tab, load]);

  const fig = desk.figures;
  const tile = (label: string, key: string, v: string, sub?: string, colour?: string): [string, string, string | null, string | undefined, string] =>
    [label, String(fig[key] ?? 0), colour ?? null, sub, `/partnerships?view=${v}`];
  const tabs: [Tab, string][] = [["dashboard", "Dashboard"], ["proposals", "Proposals"]];
  if (can(desk, "VIEW_REPORTS")) tabs.push(["reports", "Reports"]);
  if (can(desk, "MANAGE_PARTNERSHIP_SETTINGS")) tabs.push(["settings", "Settings"]);
  const deps = desk.departments.filter((d) => !f.faculty || d.faculty_code === f.faculty);

  return (
    <div className="stack">
      <PageHead description="Proposals from organisations: received, screened, routed, reviewed, decided and followed through to their outcomes."
        actions={can(desk, "CREATE_PARTNERSHIP") ? <Btn kind="secondary" onClick={() => setRecording(true)}>Record a proposal</Btn> : null} />
      <Tabs items={tabs.map(([v, label]) => ({ id: v, label }))} value={tab} onChange={(v) => setTab(v)} label="Partnerships" />

      {tab === "dashboard" ? (
        <Tiles cls="grid--4" items={[
          tile("Total received", "total", "ALL"), tile("New", "new", "PENDING", "Received, not yet screened"),
          tile("Under review", "underReview", "PENDING"), tile("Awaiting information", "awaitingInformation", "AWAITING", undefined, (fig.awaitingInformation ?? 0) ? "var(--chrome)" : undefined),
          tile("Due diligence", "dueDiligence", "DUE_DILIGENCE"), tile("Pending approval", "pendingApproval", "APPROVAL"),
          tile("Agreement review", "agreementReview", "AGREEMENTS"), tile("Active partnerships", "active", "ACTIVE", undefined, "var(--green-ink)"),
          tile("Declined", "declined", "ALL"), tile("Closed", "closed", "ALL"),
          tile("Overdue", "overdue", "OVERDUE", "Past the due date", (fig.overdue ?? 0) ? "var(--red-ink)" : undefined),
          tile("Compliance review", "complianceReview", "COMPLIANCE", "Flags raised for review"),
          tile("Unassigned", "unassigned", "UNASSIGNED", "No owner yet", (fig.unassigned ?? 0) ? "var(--red-ink)" : undefined),
          tile("My assignments", "mine", "MINE"), tile("Reviews asked of my office", "myReviews", "REVIEWS"),
          tile("Expiring agreements", "expiring", "EXPIRING", "Within the alert window"),
        ]} />
      ) : null}

      {tab === "proposals" ? (
        <Panel title={VIEWS.find(([v]) => v === view)?.[1] ?? "Proposals"} right={list ? <span className="sub2">{list.total} found</span> : null}>
          <PBody>
            <div className="grid grid--4">
              <Field id="pt-view" label="Show">
                <select id="pt-view" className="ctl" value={view} onChange={(e) => { setView(e.target.value); setPage(0); }}>
                  {VIEWS.map(([v, l]) => <option key={v} value={v}>{l}</option>)}
                </select>
              </Field>
              <Field id="pt-q" label="Search" hint="Reference, organisation, title or email">
                <input id="pt-q" className="ctl" value={f.q} onChange={(e) => { setF({ ...f, q: e.target.value }); setPage(0); }} />
              </Field>
              <Field id="pt-status" label="Status">
                <select id="pt-status" className="ctl" value={f.status} onChange={(e) => { setF({ ...f, status: e.target.value }); setPage(0); }}>
                  <option value="">Any</option>{Object.entries(STATUS_WORDS).filter(([k]) => k !== "DRAFT").map(([k, [l]]) => <option key={k} value={k}>{l}</option>)}
                </select>
              </Field>
              <Field id="pt-group" label="Category">
                <select id="pt-group" className="ctl" value={f.category || (f.group ? `g:${f.group}` : "")} onChange={(e) => {
                  const v = e.target.value; setF({ ...f, group: v.startsWith("g:") ? v.slice(2) : "", category: v.startsWith("g:") ? "" : v }); setPage(0);
                }}>
                  <option value="">Any</option>
                  {desk.groups.map((g) => (
                    <optgroup key={g.code} label={g.label}>
                      <option value={`g:${g.code}`}>All of {g.label}</option>
                      {desk.categories.filter((c) => c.grp === g.code).map((c) => <option key={c.code} value={c.code}>{c.label}</option>)}
                    </optgroup>
                  ))}
                </select>
              </Field>
              <Field id="pt-fac" label="Faculty">
                <select id="pt-fac" className="ctl" value={f.faculty} onChange={(e) => { setF({ ...f, faculty: e.target.value, dept: "" }); setPage(0); }}>
                  <option value="">Any</option>{desk.faculties.map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}
                </select>
              </Field>
              <Field id="pt-dept" label="Department">
                <select id="pt-dept" className="ctl" value={f.dept} onChange={(e) => { setF({ ...f, dept: e.target.value }); setPage(0); }}>
                  <option value="">Any</option>{deps.map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}
                </select>
              </Field>
              <Field id="pt-country" label="Country"><input id="pt-country" className="ctl" value={f.country} onChange={(e) => { setF({ ...f, country: e.target.value }); setPage(0); }} /></Field>
              <Field id="pt-funding" label="Funding">
                <select id="pt-funding" className="ctl" value={f.funding} onChange={(e) => { setF({ ...f, funding: e.target.value }); setPage(0); }}>
                  <option value="">Any</option>{FUNDING.map(([k, l]) => <option key={k} value={k}>{l}</option>)}
                </select>
              </Field>
              <Field id="pt-scope" label="International/local">
                <select id="pt-scope" className="ctl" value={f.scope} onChange={(e) => { setF({ ...f, scope: e.target.value }); setPage(0); }}>
                  <option value="">Either</option><option value="INTERNATIONAL">International</option><option value="LOCAL">Local</option>
                </select>
              </Field>
              <Field id="pt-comp" label="Compliance">
                <select id="pt-comp" className="ctl" value={f.compliance} onChange={(e) => { setF({ ...f, compliance: e.target.value }); setPage(0); }}>
                  <option value="">Any</option><option value="REQUIRED">Compliance review required</option>
                  {Object.entries(FLAG_WORDS).map(([k, l]) => <option key={k} value={k}>Flag: {l}</option>)}
                </select>
              </Field>
              <Field id="pt-owner" label="Owner">
                <select id="pt-owner" className="ctl" value={f.owner} onChange={(e) => { setF({ ...f, owner: e.target.value }); setPage(0); }}>
                  <option value="">Anyone</option><option value="ME">Me</option><option value="NONE">Unassigned</option>
                  {desk.owners.map((o) => <option key={o.id} value={o.id}>{o.name}</option>)}
                </select>
              </Field>
              <Field id="pt-desk" label="Desk">
                <select id="pt-desk" className="ctl" value={f.desk} onChange={(e) => { setF({ ...f, desk: e.target.value }); setPage(0); }}>
                  <option value="">Any</option>{desk.desks.map((d) => <option key={d.code} value={d.code}>{d.label}</option>)}
                </select>
              </Field>
              <Field id="pt-from" label="Received from"><input id="pt-from" type="date" className="ctl" value={f.from} onChange={(e) => { setF({ ...f, from: e.target.value }); setPage(0); }} /></Field>
              <Field id="pt-to" label="Received to"><input id="pt-to" type="date" className="ctl" value={f.to} onChange={(e) => { setF({ ...f, to: e.target.value }); setPage(0); }} /></Field>
            </div>
            <div className="row mt-1"><Btn kind="ghost" onClick={() => { setF(BLANK); setPage(0); }}>Clear filters</Btn></div>
          </PBody>
          {problem ? <PBody><ProblemNotice problem={problem} /></PBody> : !list ? <PBody><div className="row row--tight sub2"><Spinner /> Reading…</div></PBody> : (
            <>
              <div className="tablewrap" tabIndex={0}>
                <table className="tbl--data" style={{ minWidth: 1100 }}>
                  <thead><tr>
                    <th className="mid">S/N</th><th>Reference</th><th>Organisation</th><th>Country</th><th>Category</th><th>Title</th><th>Faculty</th><th>Department</th>
                    <th>Status</th><th>Owner</th><th>Received</th><th>Last updated</th><th>Next action</th><th>Due</th><th />
                  </tr></thead>
                  <tbody>
                    {list.rows.map((r, i) => (
                      <tr key={r.id}>
                        <td className="mid tnum">{page * list.size + i + 1}</td>
                        <td className="tnum b600">{r.reference}</td>
                        <td>{r.org_name}</td><td className="sub2">{r.country ?? "—"}</td><td className="sub2">{r.category_label ?? "—"}</td>
                        <td>{r.title}{r.compliance_review ? <div><Pil kind="warn">Compliance review</Pil></div> : null}</td>
                        <td className="sub2">{r.faculty ?? "—"}</td><td className="sub2">{r.department ?? "—"}</td>
                        <td><Pil kind={STATUS_WORDS[r.status]?.[1] ?? "grey"}>{statusWord(r.status)}</Pil></td>
                        <td className="sub2">{r.owner_name ?? <span className="ink-red">Unassigned</span>}</td>
                        <td className="sub2">{dateWords(r.received_at)}</td><td className="sub2">{dateWords(r.updated_at)}</td>
                        <td className="sub2">{r.next_action ?? "—"}</td>
                        <td className={`sub2${r.overdue ? " ink-red b600" : ""}`}>{r.due_on ? dateWords(r.due_on) : "—"}{r.overdue ? " (overdue)" : ""}</td>
                        <td><Link className="btn btn--ghost btn--sm" href={`/partnerships/${r.id}`}>Open<span className="sr-only"> {r.reference}</span></Link></td>
                      </tr>
                    ))}
                    {!list.rows.length ? <tr><td colSpan={15} className="sub2">No proposal matches.</td></tr> : null}
                  </tbody>
                </table>
              </div>
              <PBody>
                <div className="row" style={{ justifyContent: "space-between", flexWrap: "wrap", gap: 8 }}>
                  <span className="sub2">{list.total ? `${page * list.size + 1}–${Math.min(list.total, (page + 1) * list.size)} of ${list.total}` : "None"}</span>
                  <div className="row" style={{ gap: 6 }}>
                    <Btn kind="ghost" disabled={page === 0} onClick={() => setPage(page - 1)}>Previous</Btn>
                    <Btn kind="ghost" disabled={(page + 1) * list.size >= list.total} onClick={() => setPage(page + 1)}>Next</Btn>
                  </div>
                </div>
              </PBody>
            </>
          )}
        </Panel>
      ) : null}

      {tab === "reports" ? <Reports desk={desk} /> : null}
      {tab === "settings" ? <Settings /> : null}
      {recording ? <RecordProposal desk={desk} onClose={() => setRecording(false)} onSaved={(id) => router.push(`/partnerships/${id}`)} /> : null}
    </div>
  );
}
