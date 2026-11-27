"use client";

/** V779 · the Summer's students: everyone with a selection or a charge (the default), the students identified as eligible, or every
 *  undergraduate the engine reads — paged and filtered by the server, which adds the figures over the whole list. A Head of
 *  Department sees their department's students, a Dean their faculty's. The list downloads as a CSV the API makes (and records on
 *  the export log). */
import Link from "next/link";
import { useState } from "react";
import { Btn, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { Field } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { useQueryNav } from "@/lib/query-nav";
import type { Problem } from "@/lib/api";
import { day } from "@/lib/format";
import {
  categoryPill, deskHref, naira, notEligibleWord, num, paymentStateWords, plural, sessionPath, type SummerRosterView,
} from "@/lib/summer";
import { saveFile } from "./deskApi";
import { OrgFilters } from "./OrgFilters";
import type { OrgOptions } from "@/lib/summer-org";

const SCOPE_WORD: Record<string, string> = { SELECTED: "Students with a selection", ELIGIBLE: "Eligible students", ALL: "Every undergraduate" };

export function SummerRoster({ session, view, filters, page, org }: { session: string; view: SummerRosterView; filters: Record<string, string>; page: number; org: OrgOptions }) {
  const go = useQueryNav();
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const s = view.summary;
  const scope = filters.scope || "SELECTED";
  function nav(patch: Record<string, string>, toPage = 1) {
    const next: Record<string, string> = { ...filters, ...patch };
    for (const k of Object.keys(next)) if (!next[k]) delete next[k];
    go(deskHref(session, "students", next, toPage));
  }
  const filtered = Object.keys(filters).some((k) => filters[k] && k !== "scope");
  async function exportCsv() {
    setBusy(true);
    setProblem(null);
    try {
      const qs = new URLSearchParams(filters).toString();
      const p = await saveFile(`/summer/${sessionPath(session)}/students/export${qs ? `?${qs}` : ""}`, `summer-${session.replace("/", "-")}-students.csv`, `Summer Semester ${session}: students exported`);
      if (p) { setProblem(p); notifyProblem(p); return; }
      notify("The students are downloaded");
    } finally {
      setBusy(false);
    }
  }
  const pages = Math.max(1, Math.ceil(view.total / view.size));
  const first = view.total ? (page - 1) * view.size + 1 : 0;
  const last = Math.min(view.total, page * view.size);
  const tile = (label: string, value: number | string | undefined | null, cap: string): [string, string, null, string] | null => (value === undefined || value === null ? null : [label, String(value), null, cap]);
  const figures = [
    tile("Eligible", s?.eligible, view.identifiedAt ? `As identified ${day(view.identifiedAt)}` : "Not yet identified"),
    tile("Begun", s?.commenced, `${s?.owing ?? 0} owing · ${s?.paid ?? 0} paid in full`),
    tile("Registered", s?.completed, `${s?.registeredCourses ?? 0} course registrations`),
    tile("Missing results", s?.missingHistoryStudents, "Students with no published result on the portal"),
  ].filter((t): t is [string, string, null, string] => t !== null);
  const money = [
    s?.programmeFeesPaid !== undefined ? ["Programme fees paid", naira(s.programmeFeesPaid), null, "Charged once a student a Summer"] as [string, string, null, string] : null,
    s?.courseFeesPaid !== undefined ? ["Course fees paid", naira(s.courseFeesPaid), null, "A fee a course registered"] as [string, string, null, string] : null,
    s?.feesPaid !== undefined && s?.programmeFeesPaid === undefined ? ["Fees paid", naira(s.feesPaid), null, "Programme and course fees"] as [string, string, null, string] : null,
    s?.feesOutstanding !== undefined ? ["Owed, not yet paid", naira(s.feesOutstanding), null, "Selected and unpaid"] as [string, string, null, string] : null,
  ].filter((t): t is [string, string, null, string] => t !== null);
  return (
    <>
      {figures.length ? <Tiles items={figures} cls={figures.length === 3 ? "grid--3" : "grid--4"} /> : null}
      {money.length ? <Tiles items={money} cls={money.length === 3 ? "grid--3" : "grid--4"} /> : null}
      <form className="filterbar" role="search" onSubmit={(e) => { e.preventDefault(); nav({ q: String(new FormData(e.currentTarget).get("q") ?? "").trim() }); }}>
        <div className="row" style={{ width: "100%" }}>
          <Field id="sr-scope" label="Show" style={{ flex: "0 1 220px" }}>
            <select id="sr-scope" className="ctl" value={scope} onChange={(e) => nav({ scope: e.target.value === "SELECTED" ? "" : e.target.value })}>
              {Object.entries(SCOPE_WORD).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
            </select>
          </Field>
          <OrgFilters idp="sr" filters={filters} onChange={(p) => nav(p)} org={org} />
          <Field id="sr-cat" label="Category" style={{ flex: "0 1 170px" }}>
            <select id="sr-cat" className="ctl" value={filters.category ?? ""} onChange={(e) => nav({ category: e.target.value })}>
              <option value="">Any</option><option value="FINAL_YEAR">Final-year</option><option value="SPILLOVER">Spillover</option><option value="AUTHORISED">Authorised</option>
            </select>
          </Field>
          <Field id="sr-pay" label="Payment" style={{ flex: "0 1 150px" }}>
            <select id="sr-pay" className="ctl" value={filters.pay ?? ""} onChange={(e) => nav({ pay: e.target.value })}>
              <option value="">Any</option><option value="NOT_STARTED">Not started</option><option value="UNPAID">Unpaid</option><option value="PART_PAID">Part paid</option><option value="PAID">Paid</option>
            </select>
          </Field>
          <Field id="sr-reg" label="Registration" style={{ flex: "0 1 170px" }}>
            <select id="sr-reg" className="ctl" value={filters.reg ?? ""} onChange={(e) => nav({ reg: e.target.value })}>
              <option value="">Any</option><option value="REGISTERED">Registered</option><option value="NOT_REGISTERED">Not registered</option>
            </select>
          </Field>
          <Field id="sr-q" label="Search" style={{ flex: "2 1 220px" }}>
            <input id="sr-q" name="q" className="ctl" type="search" defaultValue={filters.q ?? ""} key={filters.q ?? ""} placeholder="Number, name or programme" autoComplete="off" />
          </Field>
          <div className="row row--tight" style={{ alignSelf: "flex-end" }}>
            <Btn kind="primary" type="submit">Search</Btn>
            {filtered ? <Btn kind="ghost" onClick={() => go(deskHref(session, "students", scope === "SELECTED" ? {} : { scope }))}>Clear</Btn> : null}
          </div>
        </div>
      </form>
      <Panel title="Students" right={<span className="row row--inline row--tight">
        <span>{view.total ? `${first}–${last} of ${view.total.toLocaleString()}` : "None"}</span>
        <Btn kind="ghost" size="sm" busy={busy} busyLabel="Preparing…" disabled={busy || !view.total} onClick={() => void exportCsv()}>Export CSV</Btn>
      </span>}>
        {view.rows.length ? (
          <DTable pageSize={0} noPrint title="Summer Semester students"
            cols={["Student", "Programme · level", "Category", "Selections", "Paid · owed|num", "Payment", "Results"]}
            rows={view.rows.map((r) => {
              const [pw, pt] = paymentStateWords(r.payment_state);
              const k = r.student_id;
              const decided = r.not_outstanding + r.rejected;
              return [
                <span key={`n${k}`}><Link className="lnk b600" href={`/students/${r.student_id}`}>{r.name}</Link><span className="blk sub2 tnum">{r.matric_no ?? "—"}</span></span>,
                <span key={`p${k}`}><span className="sub2">{r.programme ?? "—"}</span><span className="blk sub2 tnum">{r.level ?? "—"} Level{r.summer_level && r.summer_level !== r.level ? ` · Summer level ${r.summer_level}` : ""}</span></span>,
                r.eligible ? <Pil key={`e${k}`} kind="ok">{categoryPill(r.category)}</Pil> : <span key={`e${k}`} className="sub2" title={notEligibleWord(r.reason)}>{r.reason ? r.reason.replaceAll("_", " ").toLowerCase() : "—"}</span>,
                <span key={`s${k}`}>
                  <span className="tnum">{plural(r.selected, "course")}{r.units ? ` · ${plural(r.units, "unit")}` : ""}</span>
                  {r.selected || decided ? <span className="blk sub2 tnum">{r.pending} pending · {r.confirmed} confirmed{decided ? ` · ${decided} not outstanding or rejected` : ""}</span> : null}
                  {r.flagged ? <span className="blk sub2">{r.flagged} to review</span> : null}
                  {r.clarifications ? <span className="blk sub2">{r.clarifications} asked</span> : null}
                  {r.courses_paid ? <span className="blk sub2 tnum">{r.courses_paid} paid</span> : null}
                </span>,
                <span key={`m${k}`} className="tnum">{naira(num(r.programme_fee_paid) + num(r.course_fees_paid))}<span className="blk sub2">owes {naira(num(r.programme_fee_due) + num(r.course_fees_due))}</span></span>,
                <Pil key={`ps${k}`} kind={pt}>{pw.toUpperCase()}</Pil>,
                <span key={`r${k}`} className="sub2">{r.results_published ? `${r.results_passed} passed · ${r.results_failed} failed` : r.results === 0 ? "No result on the portal" : "—"}</span>,
              ];
            })} />
        ) : <PBody><div className="sub2">{filtered ? "No student matches these filters." : scope === "SELECTED" ? "No student has selected a course yet." : "No student to show."}</div></PBody>}
        <PBody>
          <div className="row row--base">
            <span className="sub2">Page {page} of {pages}</span>
            <span className="grow" />
            <Btn kind="ghost" size="sm" disabled={page <= 1} onClick={() => nav({}, page - 1)}>Previous</Btn>
            <Btn kind="ghost" size="sm" disabled={page >= pages} onClick={() => nav({}, page + 1)}>Next</Btn>
          </div>
          {problem ? <ProblemNotice problem={problem} /> : null}
        </PBody>
      </Panel>
    </>
  );
}
