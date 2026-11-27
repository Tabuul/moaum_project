"use client";

/** V779 · the Summer's reports for the Academic Office, the Faculties and Departments, the Bursary and ICT: the figures of the
 *  eligible, of what was selected and how the Office decided it, of registration and of the money, overall or by faculty, department,
 *  programme, level or category, narrowed by the filters. A Head of Department or a Dean sees only their own unit's, and the page
 *  says so. The Bursary reads the money columns; the CSV is the API's, and is recorded on the export log. */
import { useState } from "react";
import { Btn, Panel, PBody, Note, Tabs } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { useQueryNav } from "@/lib/query-nav";
import type { Problem } from "@/lib/api";
import { STATE_FILTER_WORD, VERIFICATIONS, deskHref, naira, reportRow, reportTotal, scopeLine, sessionPath, type SummerReportView } from "@/lib/summer";
import { saveFile } from "./deskApi";
import { OrgFilters } from "./OrgFilters";
import type { OrgOptions } from "@/lib/summer-org";

const GROUPS: { id: string; label: string; head: string }[] = [
  { id: "ALL", label: "Overall", head: "All students" }, { id: "FACULTY", label: "Faculty", head: "Faculty" }, { id: "DEPARTMENT", label: "Department", head: "Department" },
  { id: "PROGRAMME", label: "Programme", head: "Programme" }, { id: "LEVEL", label: "Level", head: "Summer level" }, { id: "CATEGORY", label: "Category", head: "Category" },
];

export function SummerReports({ session, view, filters, org }: { session: string; view: SummerReportView; filters: Record<string, string>; org: OrgOptions }) {
  const go = useQueryNav();
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const group = filters.group || "ALL";
  const head = GROUPS.find((g) => g.id === group)?.head ?? "Group";
  const rows = view.rows.map((r) => reportRow(r as unknown as Record<string, unknown>));
  function nav(patch: Record<string, string>) {
    const next: Record<string, string> = { ...filters, ...patch };
    for (const k of Object.keys(next)) if (!next[k]) delete next[k];
    go(deskHref(session, "reports", next));
  }
  const filtered = Object.keys(filters).some((k) => filters[k] && k !== "group");
  async function download() {
    setBusy(true);
    setProblem(null);
    try {
      const qs = new URLSearchParams(filters).toString();
      const p = await saveFile(`/summer/${sessionPath(session)}/report/export${qs ? `?${qs}` : ""}`, `summer-${session.replace("/", "-")}-report.csv`, `Summer Semester ${session}: report exported`);
      if (p) { setProblem(p); notifyProblem(p); return; }
      notify("The report is downloaded");
    } finally {
      setBusy(false);
    }
  }
  const label = (r: (typeof rows)[number]) => (group === "ALL" ? "All students" : r.groupName ?? r.groupCode ?? "—");
  const num0 = (n: number) => <span className="tnum">{n.toLocaleString()}</span>;
  const total = group !== "ALL" && rows.length > 1;
  const sum = (k: Parameters<typeof reportTotal>[1]) => reportTotal(rows, k);
  const line = scopeLine(view.scope);
  return (
    <>
      <Tabs label="Group the figures by" value={group} onChange={(g) => nav({ group: g === "ALL" ? "" : g })} items={GROUPS.map((g) => ({ id: g.id, label: g.label }))} />
      <form className="filterbar" onSubmit={(e) => e.preventDefault()}>
        <div className="row" style={{ width: "100%" }}>
          <OrgFilters idp="rp" filters={filters} onChange={(p) => nav(p)} org={org} />
          <Field id="rp-cat" label="Category" style={{ flex: "0 1 170px" }}>
            <select id="rp-cat" className="ctl" value={filters.category ?? ""} onChange={(e) => nav({ category: e.target.value })}>
              <option value="">Any</option><option value="FINAL_YEAR">Final-year</option><option value="SPILLOVER">Spillover</option><option value="AUTHORISED">Authorised</option>
            </select>
          </Field>
          <Field id="rp-state" label="Verification" style={{ flex: "0 1 190px" }}>
            <select id="rp-state" className="ctl" value={filters.state ?? ""} onChange={(e) => nav({ state: e.target.value })}>
              <option value="">Every state</option>
              {VERIFICATIONS.map((v) => <option key={v} value={v}>{STATE_FILTER_WORD[v]}</option>)}
            </select>
          </Field>
          <Field id="rp-pay" label="Payment" style={{ flex: "0 1 150px" }}>
            <select id="rp-pay" className="ctl" value={filters.pay ?? ""} onChange={(e) => nav({ pay: e.target.value })}>
              <option value="">Any</option><option value="NOT_STARTED">Not started</option><option value="UNPAID">Unpaid</option><option value="PART_PAID">Part paid</option><option value="PAID">Paid</option>
            </select>
          </Field>
          <Field id="rp-reg" label="Registration" style={{ flex: "0 1 170px" }}>
            <select id="rp-reg" className="ctl" value={filters.reg ?? ""} onChange={(e) => nav({ reg: e.target.value })}>
              <option value="">Any</option><option value="REGISTERED">Registered</option><option value="NOT_REGISTERED">Not registered</option>
            </select>
          </Field>
          <div className="row row--tight" style={{ alignSelf: "flex-end" }}>
            {filtered ? <Btn kind="ghost" onClick={() => go(deskHref(session, "reports", group === "ALL" ? {} : { group }))}>Clear</Btn> : null}
            <Btn kind="ghost" busy={busy} busyLabel="Preparing…" disabled={busy || !rows.length} onClick={() => void download()}>Download CSV</Btn>
          </div>
        </div>
      </form>
      {line ? <Note kind="info" title="Your office's own figures">{line}</Note> : null}
      {problem ? <ProblemNotice problem={problem} /> : null}
      {rows.length === 0 ? (
        <Panel title="Report"><PBody><div className="sub2">No figure matches these filters. The students are identified on the Period and acts tab; the figures follow what they select.</div></PBody></Panel>
      ) : (
        <>
          <Panel title="Eligibility and verification" right={view.at ? `As at ${new Date(view.at).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" })}` : undefined}>
            <DTable pageSize={0} title={`Summer Semester ${session}: eligibility and verification`}
              cols={[head, "Eligible|num", "Final-year|num", "Spillover|num", "Authorised|num", "Missing results|num", "Students selected|num", "Courses selected|num", "Pending|num", "Confirmed|num", "Not outstanding|num", "Rejected|num", "To review|num", "Asked|num"]}
              rows={rows.map((r, i) => [
                <b key={`g${i}`}>{label(r)}</b>, num0(r.eligible), num0(r.eligibleFinalYear), num0(r.eligibleSpillover), num0(r.eligibleAuthorised), num0(r.missingHistoryStudents), num0(r.studentsSelected),
                num0(r.coursesSelected), num0(r.pending), num0(r.confirmed), num0(r.notOutstanding), num0(r.rejected), num0(r.flagged), num0(r.clarifications),
              ])}
              foot={total ? ["Total", num0(sum("eligible")), num0(sum("eligibleFinalYear")), num0(sum("eligibleSpillover")), num0(sum("eligibleAuthorised")), num0(sum("missingHistoryStudents")), num0(sum("studentsSelected")),
                num0(sum("coursesSelected")), num0(sum("pending")), num0(sum("confirmed")), num0(sum("notOutstanding")), num0(sum("rejected")), num0(sum("flagged")), num0(sum("clarifications"))] : undefined} />
          </Panel>
          <Panel title="Registration and payment">
            <DTable pageSize={0} title={`Summer Semester ${session}: registration and payment`}
              cols={[head, "Registered students|num", "Registered courses|num", "Units selected|num", "Not started|num", "Unpaid|num", "Part paid|num", "Paid|num", "Fees paid|num", "Owed, unpaid|num", "Open credits|num"]}
              rows={rows.map((r, i) => [
                <b key={`g${i}`}>{label(r)}</b>, num0(r.registeredStudents), num0(r.registeredCourses), num0(r.unitsSelected), num0(r.studentsNotStarted), num0(r.studentsUnpaid), num0(r.studentsPartPaid),
                num0(r.studentsPaid), <span key={`fp${i}`} className="tnum">{naira(r.feesPaid)}</span>, <span key={`fd${i}`} className="tnum">{naira(r.feesDue)}</span>, <span key={`co${i}`} className="tnum">{naira(r.creditsOpen)}</span>,
              ])}
              foot={total ? ["Total", num0(sum("registeredStudents")), num0(sum("registeredCourses")), num0(sum("unitsSelected")), num0(sum("studentsNotStarted")), num0(sum("studentsUnpaid")), num0(sum("studentsPartPaid")),
                num0(sum("studentsPaid")), <span key="tp" className="tnum">{naira(sum("feesPaid"))}</span>, <span key="td" className="tnum">{naira(sum("feesDue"))}</span>, <span key="tc" className="tnum">{naira(sum("creditsOpen"))}</span>] : undefined} />
            <PBody><div className="sub2">Owed, unpaid: Summer fees selected and not yet paid. Open credits: money held for students whose paid course was found not outstanding or rejected, for the Bursary to apply or refund. Missing results: students with no published result on the portal, so the Office verifies what they select against the record.</div></PBody>
          </Panel>
        </>
      )}
    </>
  );
}
