"use client";

/**
 * V654: Historical Fees & Clearance — the Bursary's desk for graduates' historical school fees. The figures (each a filter of the
 * list), the graduates found on the server, each graduate's account; the Bursar's approval queue; a cohort's assessment from a
 * preview; the reports (historical fees by period, financial clearance by graduate) to Excel and PDF; the data quality; the session
 * historical fees are assessed from. The account and every rule are the database's. V665: the waivers and adjustments awaiting the
 * Bursar, and the clearance reconciliation runs.
 */
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { Btn, Note, Panel, PBody, Pil, Spinner, Tabs, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { notify } from "@/components/proto/Toast";
import type { Problem } from "@/lib/api";
import { can, FINANCIAL_WORDS, naira, num, semesterWords, SOURCE_WORDS, STATE_WORDS, type Desk, type Figures, type FinancialStatus, type StudentRow } from "@/lib/historical-fees";
import { StudentAccount } from "./StudentAccount";
import { AssessmentView } from "./AssessmentView";
import { Cohort } from "./Cohort";
import { Reports } from "./Reports";
import { WaiverQueue } from "./Waivers";
import { ReconRuns } from "./ReconRuns";
import { hfCall } from "./hf-call";

type Tab = "overview" | "students" | "approvals" | "waivers" | "recon" | "cohort" | "reports" | "quality" | "setting";
const FILTER_WORDS: Record<string, string> = {
  OUTSTANDING: "Outstanding fees", GRADUATED_OWING: "Graduated, money owed", PARTIALLY_PAID: "A semester paid in part", NO_OUTSTANDING: "No outstanding balance",
  CREDIT: "Credit / overpayment", AUTO_ASSESSED: "Every semester from the fee structure", WITH_ASSESSMENT: "With an approved assessment",
};

export interface Filters { q: string; faculty: string; programme: string; admission: string; graduation: string; financial: string; filter: string }
interface Page { total: number; page: number; size: number; rows: StudentRow[] }
interface QueueRow { id: string; reference: string; session: string; semester: number; level: number | null; amount: number | string; source: string; source_reference: string | null;
  state: string; created_at: string; submitted_at: string | null; created_by_name: string | null; mine: boolean; batch: string | null; student_id: string; surname: string;
  other_names: string; matric_no: string | null; programme: string; department: string | null; faculty: string | null; paid?: number | string; outstanding?: number | string | null }
interface Quality { byIssue: Record<string, number>; rows: { issue: string; detail: string; student_id: string; surname: string; other_names: string; matric_no: string | null; programme: string }[]; unmatchedLegacyPayments: number }

const ISSUE: Record<string, string> = { NO_ENTRY_SESSION: "No admission session", NO_GRADUATION_SESSION: "No graduation session", MISSING_FEE_STRUCTURE: "Missing fee structure",
  PENDING_APPROVAL: "Assessment awaiting the Bursar", OVERPAYMENT: "Unexpected overpayment", PROGRAMME_CHANGED: "Programme changed" };
const day = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric", timeZone: "Africa/Lagos" }) : "—");

export function HistoricalFees({ desk, figures, initialTab, initialFilters, faculties, programmes }: {
  desk: Desk; figures: Figures | null; initialTab: Tab; initialFilters: Filters; faculties: { code: string; name: string }[];
  programmes: { code: string; name: string; faculty_code: string }[];
}) {
  const router = useRouter();
  const [tab, setTab] = useState<Tab>(initialTab);
  const [f, setF] = useState<Filters>(initialFilters);
  const [page, setPage] = useState(0);
  const [list, setList] = useState<Page | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [tick, setTick] = useState(0);
  const [open, setOpen] = useState<string | null>(null);
  const [viewing, setViewing] = useState<string | null>(null);
  const [queueState, setQueueState] = useState("PENDING_BURSAR_APPROVAL");
  const [queue, setQueue] = useState<{ total: number; rows: QueueRow[] } | null>(null);
  const [quality, setQuality] = useState<Quality | null>(null);
  const [start, setStart] = useState(desk.setting.assess_from ?? "");
  const [startWhy, setStartWhy] = useState("");
  const bump = () => setTick((n) => n + 1);

  useEffect(() => {
    if (tab !== "students") return;
    let alive = true;
    const qs = new URLSearchParams({ page: String(page) });
    for (const [k, v] of Object.entries(f)) if (v) qs.set(k, v);
    void hfCall<Page>(`/students?${qs}`).then((r) => { if (!alive) return; if (r.ok) { setList(r.data); setProblem(null); } else setProblem(r.problem); });
    return () => { alive = false; };
  }, [tab, f, page, tick]);
  useEffect(() => {
    if (tab !== "approvals") return;
    let alive = true;
    void hfCall<{ total: number; rows: QueueRow[] }>(`/assessments?state=${queueState}`).then((r) => { if (alive && r.ok) setQueue(r.data); else if (alive && !r.ok) setProblem(r.problem); });
    return () => { alive = false; };
  }, [tab, queueState, tick]);
  useEffect(() => {
    if (tab !== "quality") return;
    let alive = true;
    void hfCall<Quality>("/quality").then((r) => { if (alive && r.ok) setQuality(r.data); });
    return () => { alive = false; };
  }, [tab, tick]);

  const show = (financial: string, filter = "") => { setF({ ...initialFilters, q: "", financial, filter }); setPage(0); setTab("students"); };
  const pending = figures?.assessments.find((x) => x.state === "PENDING_BURSAR_APPROVAL");
  const tabs: { id: Tab; label: string }[] = [
    { id: "overview", label: "Overview" }, { id: "students", label: "Students" },
    { id: "approvals", label: `Bursar approval${pending?.n ? ` (${pending.n})` : ""}` },
    { id: "waivers", label: `Waivers and adjustments${figures?.waivers?.pending ? ` (${figures.waivers.pending})` : ""}` },
    ...(can(desk, "VIEW_FINANCIAL_CLEARANCE") ? [{ id: "recon" as Tab, label: "Reconciliation runs" }] : []),
    ...(can(desk, "CREATE_HISTORICAL_FEE_ASSESSMENT") ? [{ id: "cohort" as Tab, label: "Cohort assessment" }] : []),
    ...(can(desk, "VIEW_HISTORICAL_FEE_REPORT") ? [{ id: "reports" as Tab, label: "Reports" }] : []),
    { id: "quality", label: "Data quality" }, { id: "setting", label: "Assessment start" },
  ];

  async function refresh() {
    const r = await hfCall<{ students: number }>("/refresh", { method: "POST", body: {}, reason: "Historical fee summaries worked out again" });
    if (!r.ok) { setProblem(r.problem); return; }
    notify(`${r.data.students.toLocaleString()} graduate${r.data.students === 1 ? "" : "s"} worked out again`);
    router.refresh();
    bump();
  }

  async function saveStart() {
    const r = await hfCall<Desk>("/setting", { method: "PUT", body: { session: start || null, reason: startWhy.trim() }, reason: `Historical fees assessed from ${start || "the first session with a fee structure"}` });
    if (!r.ok) { setProblem(r.problem); return; }
    notify("The assessment start is saved and every graduate worked out again");
    setStartWhy("");
    router.refresh();
  }

  return (
    <>
      <Panel title="Historical school fees and the graduate's financial clearance" right={`Assessed from ${desk.setting.start ?? "—"}`}>
        <PBody>
          <div className="sub2 mb-2">
            A graduate owes the school fees of each session of their record that were never paid — assessed at the fees of that session and the level they were then,
            never today&rsquo;s. Where a session&rsquo;s fee structure is missing nothing is guessed: the Students Account Officer makes an assessment from the official record and
            the Bursar approves it. Only an approved amount is owed. Graduation is never undone by a debt, and a debt never goes away with graduation.
          </div>
          <Tabs label="Historical fees" value={tab} onChange={(t) => setTab(t)} items={tabs} />
        </PBody>
      </Panel>
      {problem ? <ProblemNotice problem={problem} /> : null}

      {tab === "overview" ? (
        figures ? (
          <Panel title="Historical financial clearance" right={figures.refreshedAt ? `Worked out ${day(figures.refreshedAt)}` : "Not yet worked out in full"}>
            <PBody>
              {figures.unsummarised > 0 ? (
                <Note kind="info" title={`${figures.unsummarised.toLocaleString()} graduate${figures.unsummarised === 1 ? " is" : "s are"} not yet worked out`}
                  action={can(desk, "REVIEW_HISTORICAL_FEE_ASSESSMENT") ? <Btn kind="secondary" busyLabel="Working out…" onClick={refresh}>Work out every graduate</Btn> : undefined}>
                  The figures read each graduate&rsquo;s summary; a payment confirmed or an assessment decided updates the graduate it concerns.
                </Note>
              ) : null}
              <div className="grid grid--3">
                <Door label="Total graduated students" n={figures.graduates} sub="Graduates and approved graduands" onClick={() => show("")} />
                <Door label="Students with outstanding fees" n={figures.with_outstanding} sub={naira(figures.outstanding)} bad onClick={() => show("", "OUTSTANDING")} />
                <Door label="Students fully cleared" n={figures.cleared} sub="Nothing owed, nothing to assess" ok onClick={() => show("FINANCIALLY_CLEARED")} />
                <Door label="Requires historical review" n={figures.requires_review} sub="A semester with no fee structure or assessment" bad onClick={() => show("HISTORICAL_FEE_REVIEW_REQUIRED")} />
                <Door label="Pending Bursar approval" n={figures.pending_approval} sub={`${pending?.n ?? 0} assessment(s) awaiting the Bursar`} warn onClick={() => show("FINANCIAL_CLEARANCE_PENDING")} />
                <Door label="Partially paid" n={figures.partially_paid} sub="A semester paid in part" warn onClick={() => show("", "PARTIALLY_PAID")} />
                <Door label="Auto-assessed" n={figures.auto_assessed} sub="Every semester read from the fee structure" onClick={() => show("", "AUTO_ASSESSED")} />
                <Door label="No outstanding balance" n={figures.no_outstanding} sub="On what is assessed" onClick={() => show("", "NO_OUTSTANDING")} />
                <Door label="Graduated with a financial obligation" n={figures.graduated_with_obligation} sub="Academic status GRADUATED, money owed" bad onClick={() => show("", "GRADUATED_OWING")} />
                <Door label="Awaiting final clearance" n={figures.awaitingGraduation ?? 0} sub="Award approved; the Bursar's clearance graduates them" warn onClick={() => setTab("recon")} />
                <Door label="Waivers awaiting the Bursar" n={Number(figures.waivers?.pending ?? 0)} sub={`${naira(figures.waivers?.pending_amount)} proposed · ${naira(figures.waivers?.approved_amount)} approved in force`} warn onClick={() => setTab("waivers")} />
              </div>
              <Tiles items={[
                ["Total historical amount assessed", naira(figures.assessed), null, "Approved assessments and historical fee structures"],
                ["Total historical amount paid", naira(figures.paid), "var(--green-ink)", "Confirmed school-fee payments"],
                ["Total historical outstanding", naira(figures.outstanding), num(figures.outstanding) > 0 ? "var(--red-ink)" : null, `${naira(figures.credit)} paid beyond what is assessed`],
              ]} />
              <div className="row mt-2" style={{ flexWrap: "wrap", gap: 6 }}>
                {figures.assessments.map((x) => (
                  <Btn key={x.state} kind="ghost" onClick={() => { setQueueState(x.state); setTab("approvals"); }}>{STATE_WORDS[x.state]?.[0] ?? x.state}: {Number(x.n).toLocaleString()} · {naira(x.amount)}</Btn>
                ))}
                {figures.batchesPending ? <Btn kind="ghost" onClick={() => setTab("cohort")}>Cohort batches awaiting the Bursar: {figures.batchesPending}</Btn> : null}
              </div>
            </PBody>
          </Panel>
        ) : <Panel title="Historical financial clearance"><PBody><div className="sub2">The figures could not be read.</div></PBody></Panel>
      ) : null}

      {tab === "students" ? (
        <Panel title="Search graduated students" right={list ? `${list.total.toLocaleString()} found` : undefined}>
          <PBody>
            <div className="row row--end" style={{ flexWrap: "wrap" }}>
              <Field id="hf-q" label="Search" hint="Name, matric, JAMB, admission or application number, or the record's id">
                <input id="hf-q" className="ctl" value={f.q} onChange={(e) => { setF({ ...f, q: e.target.value }); setPage(0); }} />
              </Field>
              <Field id="hf-fac" label="Faculty">
                <select id="hf-fac" className="ctl" value={f.faculty} onChange={(e) => { setF({ ...f, faculty: e.target.value, programme: "" }); setPage(0); }}>
                  <option value="">Every faculty</option>{faculties.map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}
                </select>
              </Field>
              <Field id="hf-prog" label="Programme">
                <select id="hf-prog" className="ctl" value={f.programme} onChange={(e) => { setF({ ...f, programme: e.target.value }); setPage(0); }}>
                  <option value="">Every programme</option>
                  {programmes.filter((x) => !f.faculty || x.faculty_code === f.faculty).map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}
                </select>
              </Field>
              <Field id="hf-adm" label="Admission session">
                <select id="hf-adm" className="ctl" value={f.admission} onChange={(e) => { setF({ ...f, admission: e.target.value }); setPage(0); }}>
                  <option value="">Any</option>{desk.sessions.map((x) => <option key={x} value={x}>{x}</option>)}
                </select>
              </Field>
              <Field id="hf-grad" label="Graduation session">
                <select id="hf-grad" className="ctl" value={f.graduation} onChange={(e) => { setF({ ...f, graduation: e.target.value }); setPage(0); }}>
                  <option value="">Any</option>{desk.sessions.map((x) => <option key={x} value={x}>{x}</option>)}
                </select>
              </Field>
              <Field id="hf-fin" label="Financial status">
                <select id="hf-fin" className="ctl" value={f.financial} onChange={(e) => { setF({ ...f, financial: e.target.value, filter: "" }); setPage(0); }}>
                  <option value="">Any</option>{(Object.keys(FINANCIAL_WORDS) as FinancialStatus[]).map((k) => <option key={k} value={k}>{FINANCIAL_WORDS[k][0]}</option>)}
                </select>
              </Field>
            </div>
            {f.filter ? <div className="row mt-1"><Pil kind="info">{FILTER_WORDS[f.filter] ?? f.filter.replace(/_/g, " ").toLowerCase()}</Pil><Btn kind="ghost" onClick={() => setF({ ...f, filter: "" })}>Clear</Btn></div> : null}
          </PBody>
          {!list ? <PBody><div className="row row--tight sub2"><Spinner /> Reading…</div></PBody> : (
            <>
              <DTable cols={["S/N|num", "Student", "Programme", "Graduation", "Assessed|num", "Paid|num", "Outstanding|num", "Financial status", "Bursary clearance", "|num"]}
                rows={list.rows.map((r, i) => [
                  <span key="n" className="tnum sub2">{page * list.size + i + 1}</span>,
                  <span key="s"><strong>{r.surname}, {r.other_names}</strong><span className="blk sub2 tnum">{r.matric_no ?? r.admission_no ?? "—"}{r.jamb_reg_no ? ` · JAMB ${r.jamb_reg_no}` : ""}</span></span>,
                  <span key="p" className="sub2">{r.programme}{r.department ? <span className="blk">{r.department}</span> : null}</span>,
                  <span key="g" className="tnum">{r.graduation_session ?? "—"}</span>,
                  <span key="a" className="tnum">{r.assessed == null ? "—" : naira(r.assessed)}</span>,
                  <span key="pd" className="tnum">{r.paid == null ? "—" : naira(r.paid)}</span>,
                  <span key="o" className="tnum" style={{ color: num(r.outstanding) > 0 ? "var(--red-ink)" : undefined }}>{r.outstanding == null ? "—" : naira(r.outstanding)}{r.owing ? <span className="blk sub2">{r.owing}</span> : null}</span>,
                  r.financial_status ? <Pil key="f" kind={FINANCIAL_WORDS[r.financial_status][1]}>{FINANCIAL_WORDS[r.financial_status][0]}</Pil> : <span key="f" className="sub2">Not worked out</span>,
                  <span key="c" className="sub2">{r.bursary_clearance ? r.bursary_clearance.replace(/_/g, " ").toLowerCase() : r.clearance_ref ? "pending" : "not started"}</span>,
                  <Btn key="x" kind="secondary" onClick={() => setOpen(r.student_id)}>Review fees</Btn>,
                ])} />
              {!list.rows.length ? <PBody><div className="sub2">No graduate matches.</div></PBody> : null}
              {list.total > list.size ? (
                <PBody><div className="row row--right">
                  <Btn kind="ghost" disabled={page <= 0} onClick={() => setPage((p) => p - 1)}>Previous</Btn>
                  <span className="sub2">Page {page + 1} of {Math.ceil(list.total / list.size)}</span>
                  <Btn kind="ghost" disabled={(page + 1) * list.size >= list.total} onClick={() => setPage((p) => p + 1)}>Next</Btn>
                </div></PBody>
              ) : null}
            </>
          )}
        </Panel>
      ) : null}

      {tab === "approvals" ? (
        <Panel title="Historical fee approval" right={
          <Field id="hf-qs" label="State">
            <select id="hf-qs" className="ctl" value={queueState} onChange={(e) => setQueueState(e.target.value)}>
              {Object.keys(STATE_WORDS).map((k) => <option key={k} value={k}>{STATE_WORDS[k as keyof typeof STATE_WORDS][0]}</option>)}
              <option value="ALL">Every state</option>
            </select>
          </Field>}>
          {!queue ? <PBody><div className="row row--tight sub2"><Spinner /> Reading…</div></PBody> : queue.rows.length ? (
            <DTable cols={["S/N|num", "Student", "Matric", "Faculty", "Department", "Programme", "Session", "Semester", "Level|num", "Historical fee|num", "Paid|num", "Outstanding|num",
              "Assessment source", "Created by", "Submitted", "Status", "|num"]} rows={queue.rows.map((r, i) => [
              <span key="n" className="tnum sub2">{i + 1}</span>, <span key="s"><strong>{r.surname}, {r.other_names}</strong><span className="blk sub2 tnum">{r.reference}{r.batch ? ` · ${r.batch}` : ""}</span></span>,
              <span key="m" className="tnum sub2">{r.matric_no ?? "—"}</span>, <span key="f" className="sub2">{r.faculty ?? "—"}</span>, <span key="d" className="sub2">{r.department ?? "—"}</span>,
              <span key="p" className="sub2">{r.programme}</span>, <span key="ss" className="tnum">{r.session}</span>, <span key="se">{semesterWords(r.semester)}</span>,
              <span key="l" className="tnum">{r.level ?? "—"}</span>, <span key="a" className="tnum">{naira(r.amount)}</span>, <span key="pd" className="tnum">{naira(r.paid)}</span>,
              <span key="o" className="tnum">{r.outstanding == null ? "—" : naira(r.outstanding)}</span>,
              <span key="src" className="sub2">{SOURCE_WORDS[r.source] ?? r.source}{r.source_reference ? <span className="blk">{r.source_reference}</span> : null}</span>,
              <span key="c" className="sub2">{r.created_by_name ?? "—"}{r.mine ? " (you)" : ""}</span>, <span key="sd" className="sub2">{day(r.submitted_at)}</span>,
              <Pil key="st" kind={STATE_WORDS[r.state as keyof typeof STATE_WORDS]?.[1] ?? "grey"}>{STATE_WORDS[r.state as keyof typeof STATE_WORDS]?.[0] ?? r.state}</Pil>,
              <Btn key="v" kind="secondary" onClick={() => setViewing(r.id)}>View</Btn>,
            ])} />
          ) : <PBody><div className="sub2">Nothing {queueState === "PENDING_BURSAR_APPROVAL" ? "awaits the Bursar" : "in this state"}.</div></PBody>}
        </Panel>
      ) : null}

      {tab === "waivers" ? (
        <Panel title="Waivers and adjustments">
          <PBody>
            <div className="sub2 mb-2">A waiver or adjustment lowers what a past period owes — never a payment, never &ldquo;marked paid&rdquo;. It is proposed from the student&rsquo;s
              account with the reason, the approval it rests on and its evidence, and approved or rejected by another officer of the Bursar&rsquo;s office.</div>
            <WaiverQueue desk={desk} tick={tick} onChanged={bump} />
          </PBody>
        </Panel>
      ) : null}
      {tab === "recon" ? <ReconRuns desk={desk} faculties={faculties} programmes={programmes} onOpenStudent={setOpen} /> : null}
      {tab === "cohort" ? <Cohort desk={desk} faculties={faculties} programmes={programmes} onChanged={bump} /> : null}
      {tab === "reports" ? <Reports desk={desk} faculties={faculties} programmes={programmes} /> : null}

      {tab === "quality" ? (
        <Panel title="Historical fee data quality" right={quality ? `${quality.rows.length.toLocaleString()} found` : undefined}>
          <PBody>
            {quality ? (
              <>
                <div className="row" style={{ flexWrap: "wrap", gap: 6 }}>
                  {Object.entries(quality.byIssue).map(([k, n]) => <Pil key={k} kind="warn">{ISSUE[k] ?? k}: {n.toLocaleString()}</Pil>)}
                  <Pil kind="info">Old-portal payments not yet matched to a student: {quality.unmatchedLegacyPayments.toLocaleString()}</Pil>
                </div>
                <div className="sub2 mt-1">Unmatched old-portal payments are put right in School Fees History Reconciliation (by JAMB, application or matriculation number — never by name).</div>
              </>
            ) : <div className="row row--tight sub2"><Spinner /> Reading…</div>}
          </PBody>
          {quality?.rows.length ? (
            <DTable cols={["Issue", "Student", "Programme", "Detail", "|num"]} rows={quality.rows.map((r, i) => [
              <span key={`i${i}`}>{ISSUE[r.issue] ?? r.issue}</span>, <span key={`s${i}`}>{r.surname}, {r.other_names}<span className="blk sub2 tnum">{r.matric_no ?? "—"}</span></span>,
              <span key={`p${i}`} className="sub2">{r.programme}</span>, <span key={`d${i}`} className="sub2">{r.detail}</span>,
              <Btn key={`b${i}`} kind="ghost" onClick={() => setOpen(r.student_id)}>Review fees</Btn>,
            ])} />
          ) : null}
        </Panel>
      ) : null}

      {tab === "setting" ? (
        <Panel title="The session historical fees are assessed from">
          <PBody>
            <div className="sub2 mb-2">
              Sessions before it are not assessed and never hold a graduate&rsquo;s clearance. None chosen, it is the first session the fee setup holds a line for
              ({desk.setting.start ?? "none yet"}). Move it back once the older sessions&rsquo; fee structures are stated in School Fees Setup — every graduate is worked out again.
            </div>
            <div className="row row--end" style={{ flexWrap: "wrap" }}>
              <Field id="hf-start" label="Assess from">
                <select id="hf-start" className="ctl" value={start} disabled={!can(desk, "SET_HISTORICAL_FEE_START")} onChange={(e) => setStart(e.target.value)}>
                  <option value="">The first session with a fee structure</option>{[...desk.sessions].reverse().map((x) => <option key={x} value={x}>{x}</option>)}
                </select>
              </Field>
              <Field id="hf-why" label="Reason" hint="Ten characters at least">
                <input id="hf-why" className="ctl" value={startWhy} maxLength={400} disabled={!can(desk, "SET_HISTORICAL_FEE_START")} onChange={(e) => setStartWhy(e.target.value)} />
              </Field>
              {can(desk, "SET_HISTORICAL_FEE_START") ? <Btn kind="primary" disabled={startWhy.trim().length < 10} busyLabel="Saving…" onClick={saveStart}>Save and work out again</Btn> : null}
            </div>
            {desk.setting.set_at ? <div className="sub2 mt-2">Last set {day(desk.setting.set_at)} by {desk.setting.set_by ?? "—"}: {desk.setting.reason}</div> : null}
            {can(desk, "REVIEW_HISTORICAL_FEE_ASSESSMENT") ? <div className="mt-2"><Btn kind="secondary" busyLabel="Working out…" onClick={refresh}>Work out every graduate again</Btn></div> : null}
          </PBody>
        </Panel>
      ) : null}

      {open ? <StudentAccount studentId={open} desk={desk} onClose={() => setOpen(null)} onChanged={bump} /> : null}
      {viewing ? <AssessmentView id={viewing} desk={desk} onClose={() => setViewing(null)} onChanged={bump} /> : null}
    </>
  );
}

/** a figure that opens its records */
function Door({ label, n, sub, ok, bad, warn, onClick }: { label: string; n: number; sub: string; ok?: boolean; bad?: boolean; warn?: boolean; onClick: () => void }) {
  const color = n > 0 ? (bad ? "var(--red-ink)" : warn ? "var(--amber-ink)" : ok ? "var(--green-ink)" : undefined) : undefined;
  return (
    <button type="button" className="tile" style={{ textAlign: "left", cursor: "pointer", border: "1px solid var(--line, #ddd)" }} onClick={onClick}>
      <span className="eyebrow">{label}</span><span className="n tnum" style={{ color }}>{Number(n).toLocaleString()}</span><span className="c">{sub}</span>
    </button>
  );
}
