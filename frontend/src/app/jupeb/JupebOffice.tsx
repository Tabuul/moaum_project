"use client";

/**
 * The JUPEB Office's desk (V339). The office runs admission and academic operations — the applications and their documents,
 * eligibility, returns, admission one by one or in bulk after a preview, screening, classes, the Board's examination numbers
 * and results (each imported whole after a preview), the subjects and the approved combinations, and its settings. The fees
 * are the Bursary's: shown here, never set. Every list exports with S/N first; every act is the server's, under the officer's
 * attribution, and the page shows what the server returns.
 */
import { useCallback, useEffect, useMemo, useState, type ReactNode } from "react";
import Link from "next/link";
import type { Problem } from "@/lib/api";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { buildXlsx } from "@/lib/xlsx";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil, Tiles, KvGrid } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import {
  DOC_STATUS, EVENT_LABEL, FEE_KIND, PAPER_KIND, REQUEST_STATE, SCREENING_LABEL, STATE_SHORT, day, feeCategoryLabel, fullName, jcall, laterSessions, naira, readSheet,
  stateKind, streamLabel, when, type Candidate, type ChangeRequest, type Combination, type Doc, type Paper,
} from "@/lib/jupeb";

const STATES = ["DRAFT", "SUBMITTED", "RETURNED", "ELIGIBLE", "INELIGIBLE", "PENDING", "ADMITTED", "NOT_ADMITTED", "STUDENT", "COMPLETED", "DEFERRED", "WITHDRAWN"];

interface SessionRow { session: string; applications: number }

function useSession(initial?: string | null) {
  const [session, setSession] = useState<string>(initial ?? "");
  return [session, setSession] as const;
}

function SessionPick({ sessions, value, onChange }: { sessions: SessionRow[]; value: string; onChange: (s: string) => void }) {
  return (
    <select className="ctl" style={{ width: 160 }} aria-label="Session" value={value} onChange={(e) => onChange(e.target.value)}>
      {sessions.map((s) => <option key={s.session} value={s.session}>{s.session} ({s.applications})</option>)}
    </select>
  );
}

/* ── the dashboard ─────────────────────────────────────────────────────────────────────────────── */

interface Dash {
  session: string; sessions: SessionRow[]; window: { state: string; opens_at: string | null; closes_at: string | null };
  checkingWindow: { state: string; opens_at: string | null; closes_at: string | null };
  feeRule: { application_fee: number; checking_fee: number; acceptance_fee: number; first_percent: number };
  counts: Record<string, number>; money: { kind: string; paid: number; amount: number }[];
  byCombination: { code: string; name: string; applications: number; admitted: number; students: number }[];
  byStream: { stream: string; applications: number; admitted: number; students: number }[]; tickets: number; resultsPublished: boolean;
}

export function JupebDashboard() {
  const [session, setSession] = useSession();
  const [d, setD] = useState<Dash | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  useEffect(() => {
    let live = true;
    void jcall<Dash>(`/api/v1/jupeb/office/dashboard${session ? `?session=${encodeURIComponent(session)}` : ""}`).then((r) => {
      if (!live) return;
      if (r.ok) { setD(r.data); setProblem(null); } else setProblem(r.problem);
    });
    return () => { live = false; };
  }, [session]);
  if (problem) return <ProblemNotice problem={problem} />;
  if (!d) return <Note kind="info" title="Loading the JUPEB desk…">One moment.</Note>;
  const c = d.counts;
  const total = (k: string) => d.money.filter((m) => m.kind === k || (k === "SCHOOL" && m.kind.startsWith("SCHOOL"))).reduce((n, m) => n + Number(m.amount), 0);
  const q = (state: string) => `/jupeb/applications?session=${encodeURIComponent(d.session)}&state=${state}`;
  return (
    <>
      <PageHead title="JUPEB Office" description={`The JUPEB programme for ${d.session}: applications, admission, students, examination numbers and results.`}
        actions={<SessionPick sessions={d.sessions} value={d.session} onChange={setSession} />} />
      <div className="grid grid--2">
        <Note kind={d.window.state === "OPEN" ? "ok" : "info"} title={`JUPEB application window: ${d.window.state.toLowerCase()}`}>
          The Director of ICT opens and closes it on Portal Windows.{d.window.closes_at ? ` Closes ${when(d.window.closes_at)}.` : ""}
        </Note>
        <Note kind={d.checkingWindow.state === "OPEN" ? "ok" : "info"} title={`Admission status checking: ${d.checkingWindow.state.toLowerCase()}`}>
          Candidates pay {naira(d.feeRule.checking_fee)} once to see their status while it is open; the Director of ICT opens it on Portal Windows.{d.checkingWindow.closes_at ? ` Closes ${when(d.checkingWindow.closes_at)}.` : ""}
        </Note>
      </div>
      <Tiles items={[
        ["Applications", c.total, null, `${c.today} today · ${c.science} Science · ${c.non_science} Non-Science`, q("")],
        ["Application fee paid", c.fee_paid, null, naira(total("APPLICATION"))],
        ["Awaiting review", c.submitted, null, `${c.returned} returned to applicants`, q("SUBMITTED")],
        ["Eligible", c.eligible, null, `${c.ineligible} not eligible`, q("ELIGIBLE")],
        ["Admitted", c.admitted, "var(--green-ink)", `${c.not_admitted} not admitted · ${c.pending} pending`, q("ADMITTED,STUDENT,COMPLETED")],
        ["Checked their status", c.checking_paid, null, naira(total("STATUS_CHECKING"))],
        ["Accepted admission", c.accepted, null, naira(total("ACCEPTANCE"))],
        ["Screening cleared", c.screening_cleared, null, `${c.screening_open} still in screening`],
        ["Active students", c.students, null, `${c.registered} registered subjects`, q("STUDENT,COMPLETED")],
        ["Examination numbers", c.exam_numbers, null, "issued by the Board", "/jupeb/examination"],
        ["Change requests open", c.requests_pending, Number(c.requests_pending) > 0 ? "var(--amber)" : null, `${c.deferred} deferred · ${c.withdrawn} withdrawn this session`, "/jupeb/requests"],
        ["School fees received", naira(total("SCHOOL")), null, d.resultsPublished ? "results published" : `${c.completed} completed`, "/jupeb/payments"],
      ]} />
      <Panel title="Payments by fee">
        <PBody><DTable noPrint pageSize={0} cols={["Fee", "Payments|num", "Amount received|num"]} rows={[
          ...d.money.map((m) => [FEE_KIND[m.kind] ?? m.kind, m.paid, naira(m.amount)]),
          [<b key="t">Total</b>, d.money.reduce((n, m) => n + Number(m.paid), 0), <b key="a">{naira(d.money.reduce((n, m) => n + Number(m.amount), 0))}</b>],
        ]} /></PBody>
      </Panel>
      <div className="grid grid--2">
        <Panel title="By combination">
          <PBody><DTable pageSize={10} cols={["Code", "Combination", "Applications|num", "Admitted|num", "Students|num"]} texts={d.byCombination.map((r) => `${r.code} ${r.name}`)}
            rows={d.byCombination.map((r) => [r.code, r.name, r.applications, r.admitted, r.students])} /></PBody>
        </Panel>
        <Panel title="By programme">
          <PBody><DTable pageSize={10} cols={["Programme", "Applications|num", "Admitted|num", "Students|num"]} rows={d.byStream.map((r) => [r.stream, r.applications, r.admitted, r.students])} /></PBody>
        </Panel>
      </div>
      <Panel title="Support" right={<Link href="/helpdesk">Open the support desk</Link>}>
        <PBody><p className="sub2">{d.tickets} open ticket(s) in the JUPEB support queue.</p></PBody>
      </Panel>
    </>
  );
}

/* ── the applications ──────────────────────────────────────────────────────────────────────────── */

interface AppRow {
  id: string; application_no: string; name: string; sex: string | null; date_of_birth: string | null; phone: string | null; email: string; nin: string | null;
  state_of_origin: string | null; lga: string | null; stream: string | null; combination_code: string | null; state: string;
  fee_confirmed_at: string | null; submitted_at: string | null; admission_ref: string | null; exam_no: string | null; screening_state: string | null; class_name: string | null;
  fee_category: string | null; indigene: boolean | null; school_fee: number | null; school_fee_paid: number; school_fee_outstanding: number; school_fee_status: string; created_at: string;
  checking_paid_at: string | null; accepted_at: string | null;
}
interface AppList { session: string; total: number; page: number; size: number; rows: AppRow[] }
interface BulkRow { application_id: string; application_no: string; name: string; state: string; ok: boolean; reason: string | null }

export function JupebApplications({ canWrite, initial }: { canWrite: boolean; initial: Record<string, string> }) {
  const [filters, setFilters] = useState<Record<string, string>>({ session: "", state: "", combination: "", fee: "", screening: "", q: "", ...initial });
  const [page, setPage] = useState(0);
  const [list, setList] = useState<AppList | null>(null);
  const [sessions, setSessions] = useState<SessionRow[]>([]);
  const [combs, setCombs] = useState<Combination[]>([]);
  const [picked, setPicked] = useState<Set<string>>(new Set());
  const [bulk, setBulk] = useState<{ decision: string; note: string; rows: BulkRow[] | null } | null>(null);
  const [busy, setBusy] = useState(false);
  const [tick, setTick] = useState(0);
  const query = useMemo(() => Object.entries(filters).filter(([, v]) => v).map(([k, v]) => `${k}=${encodeURIComponent(v)}`).join("&"), [filters]);

  useEffect(() => {
    let live = true;
    void jcall<Dash>("/api/v1/jupeb/office/dashboard").then((r) => { if (live && r.ok) setSessions(r.data.sessions); });
    void jcall<Combination[]>("/api/v1/jupeb/office/combinations").then((r) => { if (live && r.ok) setCombs(r.data); });
    return () => { live = false; };
  }, []);
  useEffect(() => {
    let live = true;
    void jcall<AppList>(`/api/v1/jupeb/office/applications?${query}&page=${page}&size=50`).then((r) => { if (live) { if (r.ok) setList(r.data); else notifyProblem(r.problem); } });
    return () => { live = false; };
  }, [query, page, tick]);

  const set = (k: string, v: string) => { setFilters({ ...filters, [k]: v }); setPage(0); setPicked(new Set()); };
  async function exportAll() {
    const r = await jcall<AppList>(`/api/v1/jupeb/office/applications?${query}&page=0&size=20000`);
    if (!r.ok) { notifyProblem(r.problem); return; }
    const blob = await brandedXlsx(`JUPEB applications — ${r.data.session}`,
      ["Application No", "Name", "Sex", "Date of birth", "Phone", "Email", "NIN", "State of origin", "LGA", "Programme", "Combination", "Status",
        "Application fee", "Submitted", "Admission ref", "Status checked", "Accepted", "Fee category", "Indigene", "School fee", "Paid", "Outstanding", "Screening", "Class", "JUPEB exam no"],
      r.data.rows.map((a) => [a.application_no, a.name, a.sex, a.date_of_birth, a.phone, a.email, a.nin, a.state_of_origin, a.lga, streamLabel(a.stream),
        a.combination_code, STATE_SHORT[a.state] ?? a.state, a.fee_confirmed_at ? "Paid" : "Unpaid", day(a.submitted_at), a.admission_ref, day(a.checking_paid_at), day(a.accepted_at), feeCategoryLabel(a.fee_category),
        a.indigene == null ? "" : a.indigene ? "Yes" : "No", a.school_fee, a.school_fee_paid, a.school_fee_outstanding, a.screening_state, a.class_name, a.exam_no]),
      { sheetName: "Applications", serial: docSerial("JUPEB"), meta: Object.entries(filters).filter(([, v]) => v).map(([k, v]) => [k, v] as [string, string]) });
    downloadBlob(blob, `jupeb-applications-${r.data.session.replace("/", "-")}.xlsx`);
  }
  async function runBulk(commit: boolean) {
    if (!bulk) return;
    setBusy(true);
    try {
      const r = await jcall<{ rows: BulkRow[]; ok: number; skipped: number }>("/api/v1/jupeb/office/admission/bulk", "POST",
        { ids: [...picked], decision: bulk.decision, note: bulk.note || null, commit }, `Bulk admission: ${bulk.decision}`);
      if (!r.ok) { notifyProblem(r.problem); return; }
      if (commit) {
        notify(`${r.data.ok} decided; ${r.data.skipped} left as they were.`);
        setBulk(null); setPicked(new Set()); setTick((t) => t + 1);
      } else setBulk({ ...bulk, rows: r.data.rows });
    } finally { setBusy(false); }
  }
  const rows = list?.rows ?? [];
  const pages = list ? Math.max(1, Math.ceil(list.total / list.size)) : 1;
  return (
    <>
      <PageHead title="JUPEB applications" description="Every JUPEB candidate of the session, from draft to result. Open one to review, decide or correct it."
        actions={<Btn kind="ghost" onClick={() => void exportAll()}>Export (Excel)</Btn>} />
      <Panel title="Filter">
        <PBody>
          <div className="grid grid--4">
            <Field id="f-session" label="Session"><select id="f-session" className="ctl" value={filters.session} onChange={(e) => set("session", e.target.value)}>
              <option value="">Current</option>{sessions.map((s) => <option key={s.session} value={s.session}>{s.session}</option>)}</select></Field>
            <Field id="f-state" label="Status"><select id="f-state" className="ctl" value={filters.state} onChange={(e) => set("state", e.target.value)}>
              <option value="">All</option>{STATES.map((s) => <option key={s} value={s}>{STATE_SHORT[s]}</option>)}
              <option value="ADMITTED,STUDENT,COMPLETED">Admitted (all)</option><option value="STUDENT,COMPLETED">Students</option></select></Field>
            <Field id="f-comb" label="Combination"><select id="f-comb" className="ctl" value={filters.combination} onChange={(e) => set("combination", e.target.value)}>
              <option value="">All</option>{combs.map((c) => <option key={c.code} value={c.code}>{c.code}</option>)}</select></Field>
            <Field id="f-fee" label="Application fee"><select id="f-fee" className="ctl" value={filters.fee} onChange={(e) => set("fee", e.target.value)}>
              <option value="">All</option><option value="PAID">Paid</option><option value="UNPAID">Unpaid</option></select></Field>
            <Field id="f-scr" label="Screening"><select id="f-scr" className="ctl" value={filters.screening} onChange={(e) => set("screening", e.target.value)}>
              <option value="">All</option>{Object.entries(SCREENING_LABEL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Field>
            <Field id="f-stream" label="Programme"><select id="f-stream" className="ctl" value={filters.stream ?? ""} onChange={(e) => set("stream", e.target.value)}>
              <option value="">All</option><option value="SCIENCE">Science</option><option value="NON_SCIENCE">Non-Science</option></select></Field>
            <Field id="f-q" label="Search" hint="Name, application or exam number, email, phone, NIN"><input id="f-q" className="ctl" value={filters.q} onChange={(e) => set("q", e.target.value)} /></Field>
          </div>
        </PBody>
      </Panel>
      {canWrite && picked.size ? (
        <Note kind="info" title={`${picked.size} selected`} action={
          <div className="row">
            <Btn kind="primary" onClick={() => setBulk({ decision: "ADMITTED", note: "", rows: null })}>Admission decision…</Btn>
            <Btn kind="ghost" onClick={() => setPicked(new Set())}>Clear</Btn>
          </div>}>Decide admission for the selected applications after a preview.</Note>
      ) : null}
      <Panel title={`${list?.total ?? 0} application(s)`} right={<span className="row">
        <Btn kind="ghost" disabled={page === 0} onClick={() => setPage(page - 1)}>Previous</Btn><span className="sub2">Page {page + 1} of {pages}</span>
        <Btn kind="ghost" disabled={page + 1 >= pages} onClick={() => setPage(page + 1)}>Next</Btn></span>}>
        <PBody>
          <DTable pageSize={0} cols={[...(canWrite ? ["|mid"] : []), "S/N|num", "Application No", "Name", "Programme", "Combination", "Status", "Fee", "Submitted", "Checked", "Accepted", "Exam no"]}
            rows={rows.map((a, i) => [
              ...(canWrite ? [<input key="c" type="checkbox" aria-label={`Select ${a.application_no}`} checked={picked.has(a.id)} onChange={(e) => {
                const n = new Set(picked); if (e.target.checked) n.add(a.id); else n.delete(a.id); setPicked(n);
              }} />] : []),
              page * 50 + i + 1, <Link key="l" href={`/jupeb/applications/${a.id}`} className="tnum">{a.application_no}</Link>, a.name, streamLabel(a.stream), a.combination_code ?? "—",
              <Pil key="s" kind={stateKind(a.state)}>{STATE_SHORT[a.state] ?? a.state}</Pil>, a.fee_confirmed_at ? "Paid" : "Unpaid", day(a.submitted_at), a.checking_paid_at ? "Yes" : "—", a.accepted_at ? "Yes" : "—", a.exam_no ?? "—",
            ])} />
        </PBody>
      </Panel>
      {bulk ? (
        <Modal wide title="Admission decision for the selected applications" sub={`${picked.size} selected`} onClose={() => setBulk(null)} foot={<>
          <Btn kind="ghost" onClick={() => setBulk(null)}>Cancel</Btn>
          <Btn kind="secondary" disabled={busy} onClick={() => void runBulk(false)}>Preview</Btn>
          <Btn kind="go" disabled={busy || !bulk.rows || !bulk.rows.some((r) => r.ok)} onClick={() => void runBulk(true)}>Decide {bulk.rows ? bulk.rows.filter((r) => r.ok).length : ""}</Btn>
        </>}>
          <div className="grid grid--2">
            <Field id="b-dec" label="Decision"><select id="b-dec" className="ctl" value={bulk.decision} onChange={(e) => setBulk({ ...bulk, decision: e.target.value, rows: null })}>
              <option value="ADMITTED">Admit</option><option value="NOT_ADMITTED">Not admit</option><option value="PENDING">Pending</option></select></Field>
            <Field id="b-note" label="Note (shown to the applicant)"><input id="b-note" className="ctl" maxLength={1000} value={bulk.note} onChange={(e) => setBulk({ ...bulk, note: e.target.value })} /></Field>
          </div>
          {bulk.rows ? <DTable noPrint pageSize={0} cols={["Application No", "Name", "Now", "Result"]} rows={bulk.rows.map((r) => [r.application_no, r.name, STATE_SHORT[r.state] ?? r.state,
            r.ok ? <Pil key="o" kind="ok">Will be decided</Pil> : <Pil key="o" kind="grey">{r.reason ?? "Left as it is"}</Pil>])} /> : <p className="sub2">Preview first: each application is judged before anything is written.</p>}
        </Modal>
      ) : null}
    </>
  );
}

/* ── one application ──────────────────────────────────────────────────────────────────────────── */

interface ClassRow { id: string; session: string; name: string; capacity: number | null; combination_code: string | null; combination_name: string | null; members: number }

export function JupebApplication({ id, canWrite }: { id: string; canWrite: boolean }) {
  const [c, setC] = useState<Candidate | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [classes, setClasses] = useState<ClassRow[]>([]);
  const [modal, setModal] = useState<{ kind: string; title: string; fields: Record<string, string> } | null>(null);
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    let live = true;
    void jcall<Candidate>(`/api/v1/jupeb/office/applications/${id}`).then((r) => {
      if (!live) return;
      if (r.ok) {
        setC(r.data);
        void jcall<ClassRow[]>(`/api/v1/jupeb/office/classes?session=${encodeURIComponent(r.data.session)}`).then((k) => { if (live && k.ok) setClasses(k.data); });
      } else setProblem(r.problem);
    });
    return () => { live = false; };
  }, [id]);
  const act = useCallback(async (path: string, body: unknown, reason: string) => {
    setBusy(true);
    try {
      const r = await jcall<Candidate>(`/api/v1/jupeb/office/applications/${id}${path}`, "POST", body, reason);
      if (!r.ok) { notifyProblem(r.problem); return false; }
      setC(r.data); notify("Done."); return true;
    } finally { setBusy(false); }
  }, [id]);
  if (problem) return <ProblemNotice problem={problem} />;
  if (!c) return <Note kind="info" title="Loading the application…">One moment.</Note>;

  const open = (kind: string, title: string, fields: Record<string, string> = {}) => setModal({ kind, title, fields });
  async function submitModal() {
    if (!modal) return;
    const f = modal.fields;
    let ok = false;
    switch (modal.kind) {
      case "return": ok = await act("/return", { note: f.note }, "Returned for correction"); break;
      case "eligible": ok = await act("/eligibility", { eligible: f.eligible === "yes", note: f.note || null }, "Eligibility decided"); break;
      case "admission": ok = await act("/admission", { decision: f.decision, note: f.note || null }, "Admission decided"); break;
      case "screening": ok = await act("/screening", { decision: f.decision, reason: f.reason || null, venue: f.venue || null, at: f.at ? new Date(f.at).toISOString() : null }, "Screening decided"); break;
      case "examno": ok = await act("/exam-no", { examNo: f.examNo, reason: f.reason || null }, "Examination number set"); break;
      case "class": ok = await act("/class", { classId: f.classId || null }, "Class placement"); break;
      default: if (modal.kind.startsWith("doc:")) ok = await act(`/documents/${modal.kind.slice(4)}/review${f.sitting ? `?sitting=${f.sitting}` : ""}`, { status: f.status, note: f.note || null }, "Document reviewed");
    }
    if (ok) setModal(null);
  }
  const setF = (k: string, v: string) => modal && setModal({ ...modal, fields: { ...modal.fields, [k]: v } });
  const s = c.state;
  const pdf = (doc: string) => `/jupeb/pdf/${doc}?id=${c.id}`;
  const docBase = `/api/bff/api/v1/jupeb/office/applications/${c.id}/documents`;
  const sq = (d: Doc) => (d.sitting ? `?sitting=${d.sitting}` : "");
  const fees = c.fees;
  return (
    <>
      <PageHead title={fullName(c)} eyebrow={<Link href={`/jupeb/applications?session=${encodeURIComponent(c.session)}`}>← JUPEB applications</Link>}
        description={<>{c.application_no} · {c.session} · {streamLabel(c.stream)}{c.combination_code ? ` · ${c.combination_code}` : ""} · <Pil kind={stateKind(s)}>{STATE_SHORT[s] ?? s}</Pil></>}
        actions={<span className="row" style={{ flexWrap: "wrap" }}><LinkBtn href={pdf("summary")}>Application summary</LinkBtn>
          {c.submitted_at ? <LinkBtn href={pdf("acknowledgement")}>Acknowledgement</LinkBtn> : null}
          {c.admission_decided_at ? <LinkBtn href={pdf("status")}>Status slip</LinkBtn> : null}
          {["ADMITTED", "STUDENT", "COMPLETED"].includes(s) ? <LinkBtn href={pdf("letter")}>Admission letter</LinkBtn> : null}
          {c.accepted_at ? <LinkBtn href={pdf("acceptance")}>Acceptance letter</LinkBtn> : null}
          {c.subjects_registered_at ? <LinkBtn href={pdf("slip")}>Registration slip</LinkBtn> : null}
          {c.registered.some((r) => r.grade) ? <LinkBtn href={pdf("result")}>Statement of result</LinkBtn> : null}</span>} />
      <div className="card"><div className="card__body" style={{ display: "flex", flexDirection: "row", gap: "var(--s-4)", alignItems: "center", flexWrap: "wrap" }}>
        {c.has_passport
          // eslint-disable-next-line @next/next/no-img-element
          ? <img src={`${docBase}/PASSPORT/content?format=jpeg`} alt={`Passport photograph of ${fullName(c)}`} style={{ width: 96, height: 120, objectFit: "contain", border: "1px solid var(--line-2)", borderRadius: "var(--r-sm)" }} />
          : <div style={{ width: 96, height: 120, border: "1px dashed var(--line-2)", borderRadius: "var(--r-sm)", display: "grid", placeItems: "center", fontSize: 11, color: "var(--chrome)", textAlign: "center" }}>NO<br />PASSPORT</div>}
        <div style={{ flex: 1, minWidth: 260 }}>
          <KvGrid cls="grid--3" pairs={[["Application number", c.application_no], ["JUPEB examination number", c.exam_no ?? "Not yet assigned"], ["Programme", streamLabel(c.stream)],
            ["Combination", c.combination_code ? `${c.combination_code} — ${c.subjects.map((x) => x.title).join(", ")}` : "Not chosen"], ["Status checking fee", c.checking_paid_at ? `Paid ${day(c.checking_paid_at)}` : "Not paid"],
            ["Acceptance", c.accepted_at ? `Accepted ${day(c.accepted_at)}` : "—"]]} />
        </div>
      </div></div>
      {s === "DRAFT" || s === "RETURNED" ? <Note kind="info" title={s === "DRAFT" ? "Not yet submitted" : "Returned to the applicant"}>
        {c.steps.steps.filter((x) => !x.ok).map((x) => `${x.step.charAt(0) + x.step.slice(1).toLowerCase()}: ${x.problems.map((p) => p.message).join("; ")}`).join(" · ") || "Every step is complete."}</Note> : null}
      {canWrite ? (
        <Panel title="Decide">
          <PBody>
            <div className="row" style={{ flexWrap: "wrap" }}>
              <Btn kind="ghost" disabled={busy || !["SUBMITTED", "ELIGIBLE", "INELIGIBLE"].includes(s)} onClick={() => open("return", "Return for correction", { note: "" })}>Return for correction</Btn>
              <Btn kind="secondary" disabled={busy || !["SUBMITTED", "ELIGIBLE", "INELIGIBLE"].includes(s)} onClick={() => open("eligible", "Eligibility", { eligible: "yes", note: "" })}>Eligibility…</Btn>
              <Btn kind="primary" disabled={busy || !["ELIGIBLE", "PENDING", "NOT_ADMITTED", "ADMITTED"].includes(s)} onClick={() => open("admission", "Admission decision", { decision: "ADMITTED", note: "" })}>Admission…</Btn>
              <Btn kind="ghost" disabled={busy || !["ADMITTED", "STUDENT"].includes(s)} onClick={() => open("screening", "Screening", { decision: "SCHEDULED", reason: "", venue: c.screening_venue ?? "", at: "" })}>Screening…</Btn>
              <Btn kind="ghost" disabled={busy || !["STUDENT", "COMPLETED"].includes(s)} onClick={() => open("class", "Class", { classId: c.class_id ?? "" })}>Class…</Btn>
              <Btn kind="ghost" disabled={busy || !c.subjects_registered_at} onClick={() => open("examno", c.exam_no ? "Correct the examination number" : "Examination number", { examNo: c.exam_no ?? "", reason: "" })}>Exam number…</Btn>
            </div>
          </PBody>
        </Panel>
      ) : null}
      <div className="grid grid--2">
        <Panel title="Biodata">
          <PBody><KvGrid cls="grid--2" pairs={[
            ["Sex", c.sex === "F" ? "Female" : c.sex === "M" ? "Male" : "—"], ["Date of birth", day(c.date_of_birth)], ["NIN", c.nin ?? "—"], ["Phone", c.phone ?? "—"], ["Email", c.email],
            ["Nationality", c.nationality ?? "—"], ["State / LGA", `${c.state_of_origin ?? "—"} / ${c.lga ?? "—"}`], ["Home town", c.home_town ?? "—"], ["Contact address", c.contact_address ?? "—"],
            ["Guardian", c.guardian_name ? `${c.guardian_name} (${c.guardian_phone ?? "—"})` : "—"], ["Next of kin", c.next_of_kin_name ? `${c.next_of_kin_name} (${c.next_of_kin_phone ?? "—"}) ${c.next_of_kin_relationship ?? ""}` : "—"],
            ["Programme", streamLabel(c.stream)], ["Combination", c.combination_code ? `${c.combination_code} — ${c.subjects.map((x) => x.title).join(", ")}` : "Not chosen"],
          ]} /></PBody>
        </Panel>
        <Panel title="Status">
          <PBody><KvGrid cls="grid--2" pairs={[
            ["Application fee", c.fee_confirmed_at ? `Paid ${day(c.fee_confirmed_at)}` : "Unpaid"], ["Submitted", day(c.submitted_at)],
            ["Status checking fee", c.checking_paid_at ? `Paid ${day(c.checking_paid_at)}` : "Not paid"], ["Acceptance fee", c.accepted_at ? `Paid ${day(c.accepted_at)}` : "Not paid"],
            ["Eligibility", c.eligibility_decided_at ? `${s === "INELIGIBLE" ? "Not eligible" : "Eligible"} · ${day(c.eligibility_decided_at)}${c.decidedBy?.eligibility ? ` · ${c.decidedBy.eligibility}` : ""}` : "—"],
            ["Admission", c.admission_decided_at ? `${c.admission_ref ?? STATE_SHORT[s]} · ${day(c.admission_decided_at)}${c.decidedBy?.admission ? ` · ${c.decidedBy.admission}` : ""}` : "—"],
            ["Return note", c.return_note ?? "—"], ["Screening", c.screening_state ? `${SCREENING_LABEL[c.screening_state]}${c.screening_reason ? ` — ${c.screening_reason}` : ""}` : "—"],
            ["Activated", day(c.activated_at)], ["Class", c.class_name ?? "—"], ["Subjects registered", day(c.subjects_registered_at)], ["JUPEB exam no", c.exam_no ?? "—"],
          ]} /></PBody>
        </Panel>
      </div>
      <Panel title={`O'Level · ${c.olevel_sittings === 2 ? "two sittings" : c.olevel_sittings === 1 ? "one sitting" : "sittings not declared"}`} right={<Pil kind={c.olevelCheck.ok ? "ok" : "bad"}>{c.olevelCheck.ok ? `${c.olevelCheck.credits} credits — meets the requirement` : c.olevelCheck.reasons.join("; ") || "Not entered"}</Pil>}>
        <PBody><DTable noPrint pageSize={0} cols={["Sitting|num", "Examination", "Number", "Year", "Subject", "Grade|mid"]}
          rows={c.olevel.map((o) => [o.sitting, o.exam_type, o.exam_number ?? "—", o.exam_year ?? "—", o.subject, o.grade])} /></PBody>
      </Panel>
      <Panel title="Documents">
        <PBody><DTable noPrint pageSize={0} cols={["Document", "File", "Uploaded", "Status", ...(canWrite ? ["Review|mid"] : [])]} rows={c.documents.map((d) => [
          <span key="l">{d.label}{d.required ? "" : <span className="sub2"> · optional</span>}{d.exam_body ? <div className="sub2">{d.exam_body}{d.exam_year ? ` ${d.exam_year}` : ""}</div> : null}{d.review_note ? <div className="sub2">{d.review_note}</div> : null}</span>,
          d.filename ? <a key="f" href={`${docBase}/${d.kind}/content${sq(d)}`} target="_blank" rel="noreferrer">{d.filename}</a> : "—",
          day(d.uploaded_at), d.status ? <Pil key="s" kind={stateKind(d.status)}>{DOC_STATUS[d.status]}</Pil> : "—",
          ...(canWrite ? [d.filename ? <span key="r" className="row" style={{ gap: 4, justifyContent: "center" }}>
            <Btn kind="go" disabled={busy || d.status === "VERIFIED"} onClick={() => void act(`/documents/${d.kind}/review${sq(d)}`, { status: "VERIFIED" }, "Document verified")}>Verify</Btn>
            <Btn kind="ghost" disabled={busy} onClick={() => open(`doc:${d.kind}`, `${d.label}: needs attention`, { status: "REPLACEMENT_REQUIRED", note: "", sitting: d.sitting ? String(d.sitting) : "" })}>Problem…</Btn>
          </span> : "—"] : []),
        ])} /></PBody>
      </Panel>
      <div className="grid grid--2">
        <Panel title="Fees (the Bursary's rule)">
          <PBody>
            {fees ? <KvGrid cls="grid--2" pairs={[["Category", `${feeCategoryLabel(fees.category)} · ${fees.indigene ? "indigene" : "non-indigene"}`], ["School fee", `${naira(fees.total)}${fees.frozen ? " (charged)" : ""}`],
              ["Paid", naira(fees.paid)], ["Outstanding", naira(fees.outstanding)]]} /> : null}
            <DTable noPrint pageSize={0} cols={["Fee", "Reference", "Amount|num", "Confirmed"]} rows={c.references.map((r) => [FEE_KIND[r.kind] ?? r.kind, r.reference, naira(r.amount), r.confirmed_at ? `${day(r.confirmed_at)} · ${r.channel ?? ""}` : "—"])} />
          </PBody>
        </Panel>
        <Panel title="Subjects and results">
          <PBody>
            <DTable noPrint pageSize={0} cols={["Code", "Subject", "Grade|mid", "Points|num"]} rows={(c.registered.length ? c.registered : c.subjects.map((x) => ({ code: x.code, title: x.title, grade: null, points: null })))
              .map((r) => [r.code, r.title, r.grade ?? "—", r.points ?? "—"])} />
            {c.examNoHistory?.length ? <><div className="eyebrow mt-3">Examination number history</div>
              <DTable noPrint pageSize={0} cols={["From", "To", "Reason", "Source", "By", "When"]} rows={c.examNoHistory.map((h) => [h.old_no ?? "—", h.new_no, h.reason ?? "—", `${h.source}${h.batch_ref ? ` ${h.batch_ref}` : ""}`, h.changed_by_name ?? h.changed_office ?? "—", when(h.changed_at)])} /></> : null}
            {c.resultChanges?.length ? <><div className="eyebrow mt-3">Result corrections</div>
              <DTable noPrint pageSize={0} cols={["Subject", "From", "To", "Reason", "When"]} rows={c.resultChanges.map((h) => [h.code, h.old_grade ?? "—", h.new_grade, h.reason, when(h.changed_at)])} /></> : null}
          </PBody>
        </Panel>
      </div>
      <RequestsAndPapers c={c} canWrite={canWrite} onChange={setC} />
      <Panel title="Timeline">
        <PBody><DTable noPrint pageSize={0} cols={["When", "What", "Note", "By"]} rows={c.events.map((e) => [when(e.at), EVENT_LABEL[e.kind] ?? e.kind, e.note ?? "—", e.actor_name ?? e.actor_office ?? "—"])} /></PBody>
      </Panel>
      {modal ? (
        <Modal title={modal.title} onClose={() => setModal(null)} foot={<><Btn kind="ghost" onClick={() => setModal(null)}>Cancel</Btn><Btn kind="primary" disabled={busy} onClick={() => void submitModal()}>Save</Btn></>}>
          {modal.kind === "eligible" ? <Field id="m-el" label="Eligibility"><select id="m-el" className="ctl" value={modal.fields.eligible} onChange={(e) => setF("eligible", e.target.value)}><option value="yes">Eligible</option><option value="no">Not eligible (say why)</option></select></Field> : null}
          {modal.kind === "admission" ? <Field id="m-ad" label="Decision"><select id="m-ad" className="ctl" value={modal.fields.decision} onChange={(e) => setF("decision", e.target.value)}><option value="ADMITTED">Admit</option><option value="NOT_ADMITTED">Not admit</option><option value="PENDING">Pending</option></select></Field> : null}
          {modal.kind === "screening" ? <>
            <Field id="m-sc" label="Screening"><select id="m-sc" className="ctl" value={modal.fields.decision} onChange={(e) => setF("decision", e.target.value)}>{["SCHEDULED", "IN_PROGRESS", "CLEARED", "NOT_CLEARED", "CORRECTION_REQUIRED"].map((x) => <option key={x} value={x}>{SCREENING_LABEL[x]}</option>)}</select></Field>
            <Field id="m-ve" label="Venue"><input id="m-ve" className="ctl" maxLength={200} value={modal.fields.venue} onChange={(e) => setF("venue", e.target.value)} /></Field>
            <Field id="m-at" label="Date and time"><input id="m-at" type="datetime-local" className="ctl" value={modal.fields.at} onChange={(e) => setF("at", e.target.value)} /></Field>
            <Field id="m-re" label="Reason or instruction" hint="Required when not cleared or a correction is needed"><textarea id="m-re" className="ctl" rows={3} value={modal.fields.reason} onChange={(e) => setF("reason", e.target.value)} /></Field>
          </> : null}
          {modal.kind === "class" ? <Field id="m-cl" label="Class"><select id="m-cl" className="ctl" value={modal.fields.classId} onChange={(e) => setF("classId", e.target.value)}>
            <option value="">No class</option>{classes.map((k) => <option key={k.id} value={k.id}>{k.name}{k.combination_code ? ` (${k.combination_code})` : ""} · {k.members}{k.capacity ? `/${k.capacity}` : ""}</option>)}</select></Field> : null}
          {modal.kind === "examno" ? <>
            <Field id="m-en" label="JUPEB examination number" hint="As the Board issued it"><input id="m-en" className="ctl tnum" maxLength={40} value={modal.fields.examNo} onChange={(e) => setF("examNo", e.target.value)} /></Field>
            {c.exam_no ? <Field id="m-er" label="Reason for the correction" required><input id="m-er" className="ctl" maxLength={600} value={modal.fields.reason} onChange={(e) => setF("reason", e.target.value)} /></Field> : null}
          </> : null}
          {modal.kind.startsWith("doc:") ? <Field id="m-ds" label="Decision"><select id="m-ds" className="ctl" value={modal.fields.status} onChange={(e) => setF("status", e.target.value)}>
            <option value="REPLACEMENT_REQUIRED">Ask the applicant to replace it</option><option value="REJECTED">Reject</option><option value="UNDER_REVIEW">Under review</option></select></Field> : null}
          {"note" in modal.fields ? <Field id="m-no" label={modal.kind === "return" ? "What the applicant must correct" : "Note"} required={modal.kind === "return" || modal.kind.startsWith("doc:") || modal.fields.eligible === "no"}>
            <textarea id="m-no" className="ctl" rows={3} maxLength={1000} value={modal.fields.note} onChange={(e) => setF("note", e.target.value)} /></Field> : null}
        </Modal>
      ) : null}
    </>
  );
}

/* ── V343: change requests, verifiable papers and reminders ───────────────────────────────────── */

const OFFICE_CHANGE: Record<string, string> = {
  WITHDRAW: "Withdraw the application", DEFER: "Defer the admission", CHANGE_COMBINATION: "Change the combination", CHANGE_PROGRAMME: "Change the programme",
};

type Ask = { kind: "approve" | "decline"; req: ChangeRequest } | { kind: "revoke"; paper: Paper } | { kind: "raise" };

/** on the record: the candidate's change requests with the office's decision, the papers issued with a code, and a deferment resumed */
function RequestsAndPapers({ c, canWrite, onChange }: { c: Candidate; canWrite: boolean; onChange: (c: Candidate) => void }) {
  const [ask, setAsk] = useState<Ask | null>(null);
  const [note, setNote] = useState("");
  const [raise, setRaise] = useState<Record<string, string>>({ kind: "CHANGE_COMBINATION", combination: "", stream: c.stream === "SCIENCE" ? "NON_SCIENCE" : "SCIENCE", toSession: laterSessions(c.session)[0] ?? "", reason: "" });
  const [busy, setBusy] = useState(false);
  const pending = c.requests.find((r) => r.state === "PENDING");
  const papers = c.papers ?? [];
  async function call(path: string, body: unknown, reason: string) {
    setBusy(true);
    try {
      const r = await jcall<Candidate>(path, "POST", body, reason);
      if (!r.ok) { notifyProblem(r.problem); return; }
      onChange(r.data); notify("Done."); setAsk(null); setNote("");
    } finally { setBusy(false); }
  }
  function submit() {
    if (!ask) return;
    if (ask.kind === "approve" || ask.kind === "decline") {
      void call(`/api/v1/jupeb/office/requests/${ask.req.id}/decide`, { approve: ask.kind === "approve", note: note.trim() || null }, ask.kind === "approve" ? "JUPEB change approved" : "JUPEB change declined");
    } else if (ask.kind === "revoke") {
      void call(`/api/v1/jupeb/office/papers/${encodeURIComponent(ask.paper.code)}/revoke`, { reason: note.trim() }, "JUPEB paper revoked");
    } else {
      void call(`/api/v1/jupeb/office/applications/${c.id}/requests`, {
        kind: raise.kind, stream: raise.kind === "CHANGE_PROGRAMME" ? raise.stream : null,
        combination: raise.kind === "CHANGE_COMBINATION" || raise.kind === "CHANGE_PROGRAMME" ? raise.combination.trim() || null : null,
        toSession: raise.kind === "DEFER" ? raise.toSession.trim() : null, reason: raise.reason.trim(),
      }, "JUPEB change raised at the desk");
    }
  }
  const status = (p: Paper) => p.revoked_at ? <Pil kind="bad">Revoked</Pil> : p.current ? <Pil kind="ok">Current</Pil> : <Pil kind="warn">Superseded</Pil>;
  return (
    <>
      {c.state === "DEFERRED" ? (
        <Note kind="info" title={`Admission deferred to ${c.deferred_to ?? "—"}`}
          action={canWrite ? <Btn kind="primary" disabled={busy} onClick={() => void call(`/api/v1/jupeb/office/applications/${c.id}/resume`, {}, "Deferred JUPEB admission resumed")}>Resume in {c.deferred_to}</Btn> : null}>
          {`Deferred from ${c.deferred_from ?? c.session}. Resuming admits the candidate again in ${c.deferred_to ?? "that session"}, with the acceptance and fees already paid.`}
        </Note>
      ) : null}
      {c.state === "WITHDRAWN" ? <Note kind="bad" title="Withdrawn">{`Withdrawn${c.withdrawn_at ? ` on ${day(c.withdrawn_at)}` : ""}. The record is kept; a refund, if any, is the Bursary's decision.`}</Note> : null}
      <Panel title={`Change requests (${c.requests.length})`} right={canWrite && !pending && !["DRAFT", "RETURNED", "COMPLETED", "WITHDRAWN"].includes(c.state)
        ? <Btn kind="ghost" onClick={() => setAsk({ kind: "raise" })}>Raise for the candidate…</Btn> : null}>
        <PBody>
          <DTable noPrint pageSize={0} cols={["Asked", "Request", "Why", "By", "Decision", ...(canWrite ? ["|mid"] : [])]} rows={c.requests.map((r) => [
            when(r.requested_at), r.words, r.reason, r.requested_office === "applicant" ? "Candidate" : `Desk (${r.requested_office ?? "—"})`,
            <span key="d"><Pil kind={(REQUEST_STATE[r.state] ?? [r.state, "grey"])[1]}>{(REQUEST_STATE[r.state] ?? [r.state])[0]}</Pil>
              {r.decision_note ? <div className="sub2">{r.decision_note}</div> : null}{r.decided_by_name ? <div className="sub2">{r.decided_by_name} · {day(r.decided_at)}</div> : null}</span>,
            ...(canWrite ? [r.state === "PENDING" ? <span key="a" className="row" style={{ gap: 4, justifyContent: "center", flexWrap: "nowrap" }}>
              <Btn kind="go" disabled={busy} onClick={() => { setNote(""); setAsk({ kind: "approve", req: r }); }}>Approve…</Btn>
              <Btn kind="ghost" disabled={busy} onClick={() => { setNote(""); setAsk({ kind: "decline", req: r }); }}>Decline…</Btn></span> : "—"] : []),
          ])} />
        </PBody>
      </Panel>
      <Panel title={`Verifiable papers issued (${papers.length})`}>
        <PBody>
          <p className="sub2">Each printed statement, letter, slip and receipt carries one of these codes; anyone can check it at /verify/jupeb. A paper printed again for an unchanged record keeps its code.</p>
          <DTable noPrint pageSize={0} cols={["Code", "Paper", "Issued", "By", "Status", ...(canWrite ? ["|mid"] : [])]} rows={papers.map((p) => [
            <a key="c" className="tnum" href={`/verify/jupeb/${p.code}`} target="_blank" rel="noreferrer">{p.code}</a>,
            `${PAPER_KIND[p.kind] ?? p.kind}${p.subject_ref ? ` · ${p.subject_ref}` : ""}`, when(p.issued_at), p.issued_office ?? "—",
            <span key="s">{status(p)}{p.revoked_reason ? <div className="sub2">{p.revoked_reason}</div> : null}</span>,
            ...(canWrite ? [!p.revoked_at ? <Btn key="r" kind="ghost" onClick={() => { setNote(""); setAsk({ kind: "revoke", paper: p }); }}>Revoke…</Btn> : "—"] : []),
          ])} />
        </PBody>
      </Panel>
      {ask ? (
        <Modal title={ask.kind === "approve" ? "Approve the request" : ask.kind === "decline" ? "Decline the request" : ask.kind === "revoke" ? `Revoke ${ask.paper.code}` : "Raise a request for the candidate"}
          onClose={() => setAsk(null)} foot={<><Btn kind="ghost" onClick={() => setAsk(null)}>Cancel</Btn><Btn kind="primary" disabled={busy
            || (ask.kind === "decline" && !note.trim()) || (ask.kind === "revoke" && note.trim().length < 5) || (ask.kind === "raise" && raise.reason.trim().length < 10)}
            onClick={submit}>{ask.kind === "approve" ? "Approve" : ask.kind === "decline" ? "Decline" : ask.kind === "revoke" ? "Revoke" : "Raise"}</Btn></>}>
          {ask.kind === "approve" || ask.kind === "decline" ? (
            <>
              <p><b>{ask.req.words}</b> — {ask.req.reason}</p>
              {ask.kind === "approve" ? <p className="sub2">The change is judged again on the record as it stands and made at once; the candidate is told.</p> : null}
              <Field id="rq-note" label={ask.kind === "decline" ? "Why it is declined (the candidate reads this)" : "Note (optional)"} required={ask.kind === "decline"}>
                <textarea id="rq-note" className="ctl" rows={3} maxLength={1000} value={note} onChange={(e) => setNote(e.target.value)} /></Field>
            </>
          ) : ask.kind === "revoke" ? (
            <>
              <p>The code stops verifying: anyone checking it is told the paper is not valid. The reason is kept on the candidate&rsquo;s trail.</p>
              <Field id="pp-reason" label="Reason" required><input id="pp-reason" className="ctl" maxLength={600} value={note} onChange={(e) => setNote(e.target.value)} /></Field>
            </>
          ) : (
            <div className="grid grid--2">
              <Field id="rs-kind" label="Request"><select id="rs-kind" className="ctl" value={raise.kind} onChange={(e) => setRaise({ ...raise, kind: e.target.value })}>
                {Object.entries(OFFICE_CHANGE).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Field>
              {raise.kind === "CHANGE_PROGRAMME" ? <Field id="rs-stream" label="New programme"><select id="rs-stream" className="ctl" value={raise.stream} onChange={(e) => setRaise({ ...raise, stream: e.target.value })}>
                <option value="SCIENCE">Science</option><option value="NON_SCIENCE">Non-Science</option></select></Field> : null}
              {raise.kind === "CHANGE_COMBINATION" || raise.kind === "CHANGE_PROGRAMME" ? <Field id="rs-comb" label="New combination code" hint="e.g. SC-033"><input id="rs-comb" className="ctl" maxLength={20} value={raise.combination} onChange={(e) => setRaise({ ...raise, combination: e.target.value.toUpperCase() })} /></Field> : null}
              {raise.kind === "DEFER" ? <Field id="rs-to" label="Defer to"><select id="rs-to" className="ctl" value={raise.toSession} onChange={(e) => setRaise({ ...raise, toSession: e.target.value })}>
                {laterSessions(c.session).map((x) => <option key={x}>{x}</option>)}</select></Field> : null}
              <Field id="rs-why" label="Reason (as the candidate gave it)" required full><textarea id="rs-why" className="ctl" rows={3} maxLength={1000} value={raise.reason} onChange={(e) => setRaise({ ...raise, reason: e.target.value })} /></Field>
            </div>
          )}
        </Modal>
      ) : null}
    </>
  );
}

interface RequestRow { id: string; kind: string; state: string; words: string; reason: string; requested_at: string; requested_office: string | null; decided_at: string | null; decision_note: string | null; application_id: string; application_no: string; name: string; application_state: string; session: string }

/** /jupeb/requests — every change request, the open ones first, decided here or on the record */
export function JupebRequests({ canWrite }: { canWrite: boolean }) {
  const [state, setState] = useState("PENDING");
  const [rows, setRows] = useState<RequestRow[] | null>(null);
  const [tick, setTick] = useState(0);
  const [ask, setAsk] = useState<{ approve: boolean; row: RequestRow } | null>(null);
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    let live = true;
    void jcall<RequestRow[]>(`/api/v1/jupeb/office/requests?state=${state}`).then((r) => { if (live) { if (r.ok) setRows(r.data); else notifyProblem(r.problem); } });
    return () => { live = false; };
  }, [state, tick]);
  async function decide() {
    if (!ask) return;
    setBusy(true);
    try {
      const r = await jcall(`/api/v1/jupeb/office/requests/${ask.row.id}/decide`, "POST", { approve: ask.approve, note: note.trim() || null }, ask.approve ? "JUPEB change approved" : "JUPEB change declined");
      if (!r.ok) { notifyProblem(r.problem); return; }
      notify(ask.approve ? "Approved; the candidate is told." : "Declined; the candidate is told."); setAsk(null); setNote(""); setTick((t) => t + 1);
    } finally { setBusy(false); }
  }
  return (
    <>
      <PageHead title="JUPEB change requests" description="After submission a candidate asks — never changes — to withdraw, defer an accepted admission, or change the combination or programme. Each is judged again when approved."
        actions={<select className="ctl" aria-label="Show" value={state} onChange={(e) => setState(e.target.value)}>
          <option value="PENDING">Open</option><option value="APPROVED">Approved</option><option value="DECLINED">Declined</option><option value="CANCELLED">Cancelled</option><option value="ALL">All</option></select>} />
      <Panel title={`${rows?.length ?? 0} request(s)`}>
        <PBody>
          <DTable pageSize={50} cols={["Asked", "Application No", "Name", "Request", "Why", "Status", ...(canWrite && state === "PENDING" ? ["|mid"] : [])]}
            texts={(rows ?? []).map((r) => `${r.application_no} ${r.name} ${r.words}`)}
            rows={(rows ?? []).map((r) => [when(r.requested_at), <Link key="l" className="tnum" href={`/jupeb/applications/${r.application_id}`}>{r.application_no}</Link>, r.name, r.words, r.reason,
              <span key="s"><Pil kind={(REQUEST_STATE[r.state] ?? [r.state, "grey"])[1]}>{(REQUEST_STATE[r.state] ?? [r.state])[0]}</Pil>{r.decision_note ? <div className="sub2">{r.decision_note}</div> : null}</span>,
              ...(canWrite && state === "PENDING" ? [<span key="a" className="row" style={{ gap: 4, justifyContent: "center", flexWrap: "nowrap" }}>
                <Btn kind="go" onClick={() => { setNote(""); setAsk({ approve: true, row: r }); }}>Approve…</Btn>
                <Btn kind="ghost" onClick={() => { setNote(""); setAsk({ approve: false, row: r }); }}>Decline…</Btn></span>] : [])])} />
        </PBody>
      </Panel>
      {ask ? (
        <Modal title={ask.approve ? "Approve the request" : "Decline the request"} onClose={() => setAsk(null)}
          foot={<><Btn kind="ghost" onClick={() => setAsk(null)}>Cancel</Btn><Btn kind="primary" disabled={busy || (!ask.approve && !note.trim())} onClick={() => void decide()}>{ask.approve ? "Approve" : "Decline"}</Btn></>}>
          <p><b>{ask.row.application_no}</b> · {ask.row.name}: {ask.row.words} — {ask.row.reason}</p>
          <Field id="rq2-note" label={ask.approve ? "Note (optional)" : "Why it is declined (the candidate reads this)"} required={!ask.approve}>
            <textarea id="rq2-note" className="ctl" rows={3} maxLength={1000} value={note} onChange={(e) => setNote(e.target.value)} /></Field>
        </Modal>
      ) : null}
    </>
  );
}

interface ReminderRule { kind: string; enabled: boolean; first_after_days: number; every_days: number; max_count: number; sms: boolean; sent_30_days: number; last_sent: string | null }
interface Reminders { rules: ReminderRule[]; dueNow: { kind: string; candidates: number }[]; result?: string }
interface DueRow { application_id: string; application_no: string; name: string; kind: string; sent_before: number; last_sent: string | null }

const REMINDER_LABEL: Record<string, string> = {
  FEE_UNPAID: "Application fee not paid", SUBMIT_PENDING: "Paid but not submitted (or a correction not resubmitted)", PASSPORT_MISSING: "No passport photograph",
  CHECKING_OPEN: "Admission status not checked while checking is open", ACCEPTANCE_UNPAID: "Acceptance fee not paid", SCHOOL_FEE_UNPAID: "School fee not paid, or a balance outstanding",
};

/** the reminders the portal sends each morning at ten: when, how often, how many times, and SMS too or not */
function ReminderRules({ canWrite }: { canWrite: boolean }) {
  const [d, setD] = useState<Reminders | null>(null);
  const [edit, setEdit] = useState<Record<string, ReminderRule>>({});
  const [due, setDue] = useState<DueRow[] | null>(null);
  const [busy, setBusy] = useState(false);
  const take = (x: Reminders) => { setD(x); setEdit(Object.fromEntries(x.rules.map((r) => [r.kind, { ...r }]))); };
  useEffect(() => {
    let live = true;
    void jcall<Reminders>("/api/v1/jupeb/office/reminders").then((r) => { if (live && r.ok) take(r.data); });
    return () => { live = false; };
  }, []);
  if (!d) return null;
  const dueOf = (k: string) => Number(d.dueNow.find((x) => x.kind === k)?.candidates ?? 0);
  async function save(k: string) {
    const r0 = edit[k];
    const r = await jcall<Reminders>(`/api/v1/jupeb/office/reminders/${k}`, "PUT", { enabled: r0.enabled, firstAfterDays: Number(r0.first_after_days), everyDays: Number(r0.every_days), maxCount: Number(r0.max_count), sms: r0.sms }, "JUPEB reminder rule");
    if (!r.ok) { notifyProblem(r.problem); return; }
    take(r.data); notify("Saved.");
  }
  async function preview() {
    const r = await jcall<DueRow[]>("/api/v1/jupeb/office/reminders/due");
    if (r.ok) setDue(r.data); else notifyProblem(r.problem);
  }
  async function run() {
    setBusy(true);
    try {
      const r = await jcall<Reminders>("/api/v1/jupeb/office/reminders/run", "POST", {}, "JUPEB reminders sent now");
      if (!r.ok) { notifyProblem(r.problem); return; }
      take(r.data); setDue(null);
      const sent = (() => { try { return JSON.parse(r.data.result ?? "{}").sent ?? 0; } catch { return 0; } })();
      notify(`${sent} reminder${sent === 1 ? "" : "s"} sent.`);
    } finally { setBusy(false); }
  }
  const set = (k: string, patch: Partial<ReminderRule>) => setEdit({ ...edit, [k]: { ...edit[k], ...patch } });
  const totalDue = d.dueNow.reduce((n, x) => n + Number(x.candidates), 0);
  return (
    <Panel title="Reminders" right={<span className="row"><Btn kind="ghost" onClick={() => void preview()}>Who is due now ({totalDue})</Btn>
      {canWrite ? <Btn kind="secondary" disabled={busy || totalDue === 0} onClick={() => void run()}>{busy ? "Sending…" : "Send due reminders now"}</Btn> : null}</span>}>
      <PBody>
        <p className="sub2">Each morning at 10:00 the portal emails a candidate with an unfinished step — at most one reminder a day, on these rules. Turn one off to stop it.</p>
        <DTable noPrint pageSize={0} cols={["Reminder", "On|mid", "First after (days)|num", "Every (days)|num", "At most (times)|num", "Also SMS|mid", "Sent, 30 days|num", "Due now|num", ...(canWrite ? ["|mid"] : [])]}
          rows={d.rules.map((r) => {
            const e = edit[r.kind] ?? r;
            const num = (k: "first_after_days" | "every_days" | "max_count", min: number, max: number) => canWrite
              ? <input key={k} className="ctl tnum" style={{ width: 70, textAlign: "right" }} type="number" min={min} max={max} aria-label={`${REMINDER_LABEL[r.kind]} ${k}`} value={e[k]} onChange={(ev) => set(r.kind, { [k]: Number(ev.target.value) } as Partial<ReminderRule>)} />
              : e[k];
            return [REMINDER_LABEL[r.kind] ?? r.kind,
              <input key="on" type="checkbox" aria-label={`${REMINDER_LABEL[r.kind]} on`} disabled={!canWrite} checked={e.enabled} onChange={(ev) => set(r.kind, { enabled: ev.target.checked })} />,
              num("first_after_days", 0, 60), num("every_days", 1, 60), num("max_count", 1, 10),
              <input key="sms" type="checkbox" aria-label={`${REMINDER_LABEL[r.kind]} by SMS`} disabled={!canWrite} checked={e.sms} onChange={(ev) => set(r.kind, { sms: ev.target.checked })} />,
              r.sent_30_days, dueOf(r.kind),
              ...(canWrite ? [<Btn key="s" kind="ghost" onClick={() => void save(r.kind)}>Save</Btn>] : [])];
          })} />
        {due ? (
          <>
            <div className="eyebrow mt-3">Due now ({due.length})</div>
            <DTable pageSize={20} cols={["Application No", "Name", "Reminder", "Sent before|num", "Last sent"]} rows={due.map((x) => [
              <Link key="l" className="tnum" href={`/jupeb/applications/${x.application_id}`}>{x.application_no}</Link>, x.name, REMINDER_LABEL[x.kind] ?? x.kind, x.sent_before, x.last_sent ? when(x.last_sent) : "—"])} />
          </>
        ) : null}
      </PBody>
    </Panel>
  );
}

/* ── imports: one shape for numbers, results and combinations ─────────────────────────────────── */

interface Judged { row?: number; status: string; message: string; [k: string]: unknown }
interface ImportResult { rows: Judged[]; invalid: number; review?: number; new?: number; corrections?: number; updated?: number; unchanged?: number; committed: boolean; ref: string | null; applied: number }

function ImportBox({ title, path, aliases, template, describe, columns, cells, onDone }: {
  title: string; path: string; aliases: Record<string, string>; template: [string[], (string | number)[][]]; describe: ReactNode;
  columns: string[]; cells: (r: Judged) => ReactNode[]; onDone?: () => void;
}) {
  const [rows, setRows] = useState<Record<string, string | number>[] | null>(null);
  const [file, setFile] = useState("");
  const [res, setRes] = useState<ImportResult | null>(null);
  const [busy, setBusy] = useState(false);
  async function read(f: File | undefined) {
    if (!f) return;
    const r = await readSheet(f, aliases);
    setFile(f.name); setRows(r); setRes(null);
    if (!r.length) { notifyProblem({ status: 400, title: "No rows were found under recognised headings. Use the template." }); return; }
    await run(r, false, f.name);
  }
  async function run(r: Record<string, string | number>[], commit: boolean, name = file) {
    setBusy(true);
    try {
      const x = await jcall<ImportResult>(path, "POST", { rows: r, commit, fileName: name }, `${title} ${commit ? "committed" : "previewed"}`);
      if (!x.ok) { notifyProblem(x.problem); return; }
      setRes(x.data);
      if (commit) { notify(`${x.data.applied} row(s) written under ${x.data.ref}.`); onDone?.(); }
    } finally { setBusy(false); }
  }
  async function errors() {
    if (!res) return;
    const bad = res.rows.filter((r) => r.status === "INVALID" || r.status === "REQUIRES_REVIEW");
    const blob = await brandedXlsx(`${title} — rows to correct`, ["Row in file", "Status", "What to correct", ...columns], bad.map((r) => [r.row ?? "", r.status, r.message, ...cells(r).map((v) => (typeof v === "string" || typeof v === "number" ? v : ""))]),
      { sheetName: "Rows", serial: docSerial("JUPEBIMP"), sub: file });
    downloadBlob(blob, `${title.toLowerCase().replace(/\W+/g, "-")}-rows-to-correct.xlsx`);
  }
  return (
    <Panel title={title} right={<Btn kind="ghost" onClick={() => downloadBlob(buildXlsx(template[0], template[1], "Template"), `${title.toLowerCase().replace(/\W+/g, "-")}-template.xlsx`)}>Template</Btn>}>
      <PBody>
        <p className="sub2">{describe}</p>
        <label className="btn btn--secondary btn--sm" style={{ cursor: "pointer", width: "fit-content" }}>
          {busy ? "Reading…" : "Choose a file (.xlsx or .csv)"}<input type="file" hidden accept=".xlsx,.csv" onChange={(e) => void read(e.target.files?.[0])} />
        </label>
        {res ? (
          <div className="stack mt-3">
            <div className="row" style={{ flexWrap: "wrap" }}>
              <Pil kind={res.invalid ? "bad" : "ok"}>{res.invalid} invalid</Pil>
              {res.review != null ? <Pil kind={res.review ? "warn" : "grey"}>{res.review} need review</Pil> : null}
              {res.new != null ? <Pil kind="info">{res.new} new</Pil> : null}
              {res.corrections != null ? <Pil kind="info">{res.corrections} corrections</Pil> : null}
              {res.updated != null ? <Pil kind="info">{res.updated} updated</Pil> : null}
              {res.unchanged != null ? <Pil kind="grey">{res.unchanged} unchanged</Pil> : null}
              <span className="grow" />
              {res.invalid || res.review ? <Btn kind="ghost" onClick={() => void errors()}>Rows to correct (Excel)</Btn> : null}
              {!res.committed ? <Btn kind="go" disabled={busy || res.invalid > 0 || !rows} onClick={() => rows && void run(rows, true)}>Commit {file}</Btn> : <Pil kind="ok">Committed · {res.ref}</Pil>}
            </div>
            {res.invalid ? <Note kind="bad" title="Nothing is written while a row is invalid">Correct the rows marked invalid and upload the file again.</Note> : null}
            <DTable pageSize={25} cols={["Row|num", "Status", "Message", ...columns]} texts={res.rows.map((r) => `${r.status} ${r.message} ${cells(r).join(" ")}`)}
              rows={res.rows.map((r) => [r.row ?? "", <Pil key="s" kind={r.status === "INVALID" ? "bad" : r.status === "REQUIRES_REVIEW" ? "warn" : r.status === "UNCHANGED" ? "grey" : "ok"}>{r.status.replace("_", " ").toLowerCase()}</Pil>, r.message, ...cells(r)])} />
          </div>
        ) : null}
      </PBody>
    </Panel>
  );
}

interface Batch { ref: string; kind: string; file_name: string | null; rows: number; applied: number; imported_at: string; imported_by: string | null }

function Batches({ kind, tick }: { kind: string; tick: number }) {
  const [b, setB] = useState<Batch[]>([]);
  useEffect(() => {
    let live = true;
    void jcall<Batch[]>("/api/v1/jupeb/office/batches").then((r) => { if (live && r.ok) setB(r.data.filter((x) => x.kind === kind)); });
    return () => { live = false; };
  }, [kind, tick]);
  return (
    <Panel title="Imports so far">
      <PBody><DTable pageSize={10} cols={["Reference", "File", "Rows|num", "Applied|num", "By", "When"]} rows={b.map((x) => [x.ref, x.file_name ?? "—", x.rows, x.applied, x.imported_by ?? "—", when(x.imported_at)])} /></PBody>
    </Panel>
  );
}

export function JupebExamNumbers({ canWrite }: { canWrite: boolean }) {
  const [tick, setTick] = useState(0);
  return (
    <>
      <PageHead title="JUPEB examination numbers" description="The official numbers the Board issues, imported by application number. A number is never invented here, never shared by two candidates, and never overwritten without a reason." />
      {canWrite ? (
        <ImportBox title="Examination numbers" path="/api/v1/jupeb/office/exam-numbers/import" onDone={() => setTick((t) => t + 1)}
          aliases={{ "application number": "applicationNo", "application no": "applicationNo", "app no": "applicationNo", "appno": "applicationNo", "jupeb application number": "applicationNo",
            "examination number": "examNo", "exam number": "examNo", "exam no": "examNo", "jupeb number": "examNo", "jupeb exam no": "examNo", "jupeb examination number": "examNo", "registration number": "examNo",
            "surname": "surname", "last name": "surname", "reason": "reason", "remarks": "reason" }}
          template={[["S/N", "Application Number", "Surname", "JUPEB Examination Number", "Reason"], [[1, "JUPEB/APP/2026/000001", "ADEYEMI", "", ""]]]}
          describe={<>Matched by <b>application number</b>; the surname, when given, must agree, or the row is held for review and not applied. A candidate who already holds a different number needs a <b>reason</b> for the correction.</>}
          columns={["Application No", "Name", "Exam no", "Current"]} cells={(r) => [String(r.applicationNo ?? ""), String(r.name ?? "—"), String(r.examNo ?? ""), String(r.currentNo ?? "—")]} />
      ) : null}
      <Batches kind="EXAM_NUMBERS" tick={tick} />
    </>
  );
}

interface ResultsList { session: string; published: string | null; rows: { id: string; application_no: string; exam_no: string | null; name: string; combination_code: string | null; state: string; grades: string; points: number | null; graded: number; registered: number }[] }

export function JupebResults({ canWrite }: { canWrite: boolean }) {
  const [session, setSession] = useState("");
  const [sessions, setSessions] = useState<SessionRow[]>([]);
  const [data, setData] = useState<ResultsList | null>(null);
  const [tick, setTick] = useState(0);
  const [confirm, setConfirm] = useState(false);
  useEffect(() => {
    let live = true;
    void jcall<Dash>("/api/v1/jupeb/office/dashboard").then((r) => { if (live && r.ok) setSessions(r.data.sessions); });
    return () => { live = false; };
  }, []);
  useEffect(() => {
    let live = true;
    void jcall<ResultsList>(`/api/v1/jupeb/office/results${session ? `?session=${encodeURIComponent(session)}` : ""}`).then((r) => { if (live && r.ok) setData(r.data); });
    return () => { live = false; };
  }, [session, tick]);
  async function publish() {
    if (!data) return;
    const r = await jcall<{ completed: number }>("/api/v1/jupeb/office/results/publish", "POST", { session: data.session }, "JUPEB results published");
    if (!r.ok) { notifyProblem(r.problem); return; }
    notify(`Results published; ${r.data.completed} candidate(s) told.`); setConfirm(false); setTick((t) => t + 1);
  }
  async function exportAll() {
    if (!data) return;
    const blob = await brandedXlsx(`JUPEB results — ${data.session}`, ["Exam no", "Application No", "Name", "Combination", "Grades", "Points", "Graded", "Status"],
      data.rows.map((r) => [r.exam_no, r.application_no, r.name, r.combination_code, r.grades, r.points, `${r.graded}/${r.registered}`, STATE_SHORT[r.state] ?? r.state]), { sheetName: "Results", serial: docSerial("JUPEBRES") });
    downloadBlob(blob, `jupeb-results-${data.session.replace("/", "-")}.xlsx`);
  }
  return (
    <>
      <PageHead title="JUPEB results" description="The Board's grades, imported by examination number, one row per registered subject. Candidates see them only once published."
        actions={<span className="row"><SessionPick sessions={sessions} value={data?.session ?? session} onChange={setSession} /><Btn kind="ghost" onClick={() => void exportAll()}>Export (Excel)</Btn></span>} />
      {data?.published ? <Note kind="ok" title={`Published ${when(data.published)}`}>Candidates of {data.session} see their results. A later correction still needs its reason and is recorded.</Note> : null}
      {canWrite ? (
        <ImportBox title="Results" path="/api/v1/jupeb/office/results/import" onDone={() => setTick((t) => t + 1)}
          aliases={{ "examination number": "examNo", "exam number": "examNo", "exam no": "examNo", "jupeb exam no": "examNo", "jupeb examination number": "examNo", "application number": "applicationNo",
            "application no": "applicationNo", "subject": "subject", "subject code": "subject", "grade": "grade", "reason": "reason", "remarks": "reason" }}
          template={[["S/N", "Examination Number", "Subject", "Grade", "Reason"], [[1, "", "MTH", "A", ""]]]}
          describe={<>One row per subject: the examination number (or application number), the subject code or title, and the grade A to F. A grade already recorded changes only with a <b>reason</b>.</>}
          columns={["Candidate", "Subject", "Grade"]} cells={(r) => [String(r.name ?? r.key ?? ""), String(r.subject ?? ""), String(r.grade ?? "")]} />
      ) : null}
      <Panel title={`Results — ${data?.session ?? ""}`} right={canWrite && data && !data.published ? <Btn kind="primary" onClick={() => setConfirm(true)}>Publish results…</Btn> : null}>
        <PBody><DTable pageSize={50} cols={["Exam no", "Application No", "Name", "Combination", "Grades", "Points|num", "Graded|mid"]} texts={(data?.rows ?? []).map((r) => `${r.exam_no} ${r.application_no} ${r.name}`)}
          rows={(data?.rows ?? []).map((r) => [r.exam_no ?? "—", <Link key="l" href={`/jupeb/applications/${r.id}`}>{r.application_no}</Link>, r.name, r.combination_code ?? "—", r.grades, r.points ?? "—", `${r.graded}/${r.registered}`])} /></PBody>
      </Panel>
      <Batches kind="RESULTS" tick={tick} />
      {confirm && data ? (
        <Modal title={`Publish the ${data.session} results?`} onClose={() => setConfirm(false)} foot={<><Btn kind="ghost" onClick={() => setConfirm(false)}>Cancel</Btn><Btn kind="go" onClick={() => void publish()}>Publish</Btn></>}>
          <p>Every active student with a result is told by email and sees the result on the portal. {data.rows.filter((r) => r.graded < r.registered).length} candidate(s) are not fully graded.</p>
        </Modal>
      ) : null}
    </>
  );
}

/* ── subjects and combinations ────────────────────────────────────────────────────────────────── */

interface SubjectRow { id: string; code: string; title: string; description: string | null; active: boolean; combinations: number }
interface OfferedResult { changed: number; told: number; subjects: SubjectRow[]; combinations: Combination[] }
interface OfferAsk { kind: "subjects" | "combinations"; codes: string[]; offered: boolean; what: string }

const PROGRAMME_OF = (c: Combination) => (c.science && c.non_science ? "Both" : c.science ? "Science" : "Non-Science");

/** the catalogue (V339): the approved combinations and their subjects; V342 — the JUPEB Office disables what the University
 *  does not offer and reactivates it later, one at a time or several at once; nothing is deleted */
export function JupebCatalogue({ canWrite }: { canWrite: boolean }) {
  const [subjects, setSubjects] = useState<SubjectRow[]>([]);
  const [combs, setCombs] = useState<Combination[]>([]);
  const [tick, setTick] = useState(0);
  const [sub, setSub] = useState<Record<string, string> | null>(null);
  const [comb, setComb] = useState<Record<string, string> | null>(null);
  const [show, setShow] = useState<"all" | "offered" | "not">("all");
  const [prog, setProg] = useState<"" | "SCIENCE" | "NON_SCIENCE">("");
  const [picked, setPicked] = useState<Set<string>>(new Set());
  const [ask, setAsk] = useState<OfferAsk | null>(null);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    let live = true;
    void jcall<SubjectRow[]>("/api/v1/jupeb/office/subjects").then((r) => { if (live && r.ok) setSubjects(r.data); });
    void jcall<Combination[]>("/api/v1/jupeb/office/combinations").then((r) => { if (live && r.ok) setCombs(r.data); });
    return () => { live = false; };
  }, [tick]);
  const shown = useMemo(() => combs.filter((c) => (show === "all" || (show === "offered" ? c.offered : !c.offered))
    && (!prog || (prog === "SCIENCE" ? c.science : c.non_science))), [combs, show, prog]);
  const offeredCount = combs.filter((c) => c.offered).length;
  async function saveSubject() {
    if (!sub) return;
    const r = await jcall("/api/v1/jupeb/office/subjects", "POST", { code: sub.code, title: sub.title, description: sub.description || null, active: sub.active !== "no" }, "JUPEB subject saved");
    if (!r.ok) { notifyProblem(r.problem); return; }
    setSub(null); setTick((t) => t + 1);
  }
  async function saveComb() {
    if (!comb) return;
    const r = await jcall<ImportResult>("/api/v1/jupeb/office/combinations", "POST", { ...comb, active: comb.active !== "no" ? "YES" : "NO" }, "JUPEB combination saved");
    if (!r.ok) { notifyProblem(r.problem); return; }
    if (r.data.invalid) { notifyProblem({ status: 422, title: r.data.rows[0]?.message ?? "The combination is not valid." }); return; }
    notify("Combination saved."); setComb(null); setTick((t) => t + 1);
  }
  async function setOffered() {
    if (!ask) return;
    setBusy(true);
    try {
      const r = await jcall<OfferedResult>(`/api/v1/jupeb/office/${ask.kind}/offered`, "POST", { codes: ask.codes, offered: ask.offered, reason: reason.trim() || null },
        ask.offered ? "JUPEB: offered again" : "JUPEB: not offered");
      if (!r.ok) { notifyProblem(r.problem); return; }
      setSubjects(r.data.subjects); setCombs(r.data.combinations); setPicked(new Set()); setAsk(null); setReason("");
      notify(`${r.data.changed} ${ask.kind === "subjects" ? "subject" : "combination"}${r.data.changed === 1 ? "" : "s"} ${ask.offered ? "reactivated" : "disabled"}`
        + (r.data.told ? `; ${r.data.told} candidate${r.data.told === 1 ? "" : "s"} holding an affected combination told to choose another.` : "."));
    } finally { setBusy(false); }
  }
  const toggle = (code: string) => setPicked((p) => { const n = new Set(p); if (n.has(code)) n.delete(code); else n.add(code); return n; });
  const allShown = shown.length > 0 && shown.every((c) => picked.has(c.code));
  async function exportCombs() {
    const blob = await brandedXlsx("JUPEB subject combinations", ["Code", "Name", "Subject 1", "Subject 2", "Subject 3", "Area", "Programme", "Leads to", "Offered", "Applications"],
      shown.map((c) => [c.code, c.name, c.subject1, c.subject2, c.subject3, c.area, PROGRAMME_OF(c), (c.leads_to ?? []).join(", "), c.offered ? "Yes" : "No", c.applications]), { sheetName: "Combinations", serial: docSerial("JUPEBCOMB") });
    downloadBlob(blob, "jupeb-combinations.xlsx");
  }
  const status = (c: Combination) => c.offered ? <Pil kind="ok">Offered</Pil>
    : !c.active ? <Pil kind="grey">Disabled</Pil>
    : <Pil kind="warn">{`Not offered: ${c.subjects_not_offered.join(", ")} disabled`}</Pil>;
  const pickedWhat = `${picked.size} combination${picked.size === 1 ? "" : "s"}`;
  return (
    <>
      <PageHead title="JUPEB subjects and combinations" description="The approved combinations of three subjects, with the Board's SC codes. Disable a subject or a combination the University does not offer and reactivate it when it does — nothing is deleted, and applicants and students choose only from what is offered." />
      <KvGrid cls="grid--4" pairs={[["Combinations", combs.length], ["Offered", offeredCount], ["Not offered", combs.length - offeredCount], ["Subjects offered", `${subjects.filter((s) => s.active).length} of ${subjects.length}`]]} />
      <Panel title={`Combinations (${shown.length})`} right={<span className="row">
        <Btn kind="ghost" onClick={() => void exportCombs()}>Export (Excel)</Btn>
        {canWrite ? <Btn kind="primary" onClick={() => setComb({ code: "", name: "", subject1: "", subject2: "", subject3: "", area: "", faculties: "", programmes: "", description: "", eligibility: "", active: "yes" })}>Add combination</Btn> : null}
      </span>}>
        <PBody>
          <div className="row" style={{ gap: "var(--s-2)", marginBottom: "var(--s-2)", flexWrap: "wrap" }}>
            <select className="ctl" style={{ width: 180 }} aria-label="Show" value={show} onChange={(e) => { setShow(e.target.value as typeof show); setPicked(new Set()); }}>
              <option value="all">All combinations</option><option value="offered">Offered</option><option value="not">Not offered</option></select>
            <select className="ctl" style={{ width: 180 }} aria-label="Programme" value={prog} onChange={(e) => { setProg(e.target.value as typeof prog); setPicked(new Set()); }}>
              <option value="">Both programmes</option><option value="SCIENCE">Science</option><option value="NON_SCIENCE">Non-Science</option></select>
          </div>
          {canWrite && picked.size ? (
            <div className="row" style={{ marginBottom: "var(--s-2)" }}>
              <b>{picked.size} selected</b>
              <Btn kind="secondary" onClick={() => setAsk({ kind: "combinations", codes: [...picked], offered: false, what: pickedWhat })}>Disable selected</Btn>
              <Btn kind="secondary" onClick={() => setAsk({ kind: "combinations", codes: [...picked], offered: true, what: pickedWhat })}>Reactivate selected</Btn>
              <Btn kind="ghost" onClick={() => setPicked(new Set())}>Clear</Btn>
            </div>
          ) : null}
          <DTable pageSize={50} cols={[...(canWrite ? ["|mid"] : []), "Code", "Subjects", "Area", "Programme", "Applications|num", "Status", ...(canWrite ? ["|mid"] : [])]}
            texts={shown.map((c) => `${c.code} ${c.name} ${c.subject1} ${c.subject2} ${c.subject3} ${c.area ?? ""}`)}
            rows={shown.map((c) => [
              ...(canWrite ? [<input key="p" type="checkbox" aria-label={`Select ${c.code}`} checked={picked.has(c.code)} onChange={() => toggle(c.code)} />] : []),
              <b key="c">{c.code}</b>, `${c.subject1} · ${c.subject2} · ${c.subject3}`, c.area ?? "—", PROGRAMME_OF(c), c.applications, status(c),
              ...(canWrite ? [<span key="e" className="row" style={{ gap: "var(--s-1)", justifyContent: "center", flexWrap: "nowrap" }}>
                {c.active ? <Btn kind="ghost" onClick={() => setAsk({ kind: "combinations", codes: [c.code], offered: false, what: c.code })}>Disable</Btn>
                  : <Btn kind="ghost" onClick={() => setAsk({ kind: "combinations", codes: [c.code], offered: true, what: c.code })}>Reactivate</Btn>}
                <Btn kind="ghost" onClick={() => setComb({ code: c.code, name: c.name, subject1: c.subject1_code, subject2: c.subject2_code, subject3: c.subject3_code, area: c.area ?? "", faculties: "", programmes: "", description: c.description ?? "", eligibility: c.eligibility_notes ?? "", active: c.active ? "yes" : "no" })}>Edit</Btn>
              </span>] : []),
            ])} />
          {canWrite && shown.length ? (
            <label className="row mt-2" style={{ gap: "var(--s-1)" }}>
              <input type="checkbox" checked={allShown} onChange={() => setPicked(allShown ? new Set() : new Set(shown.map((c) => c.code)))} /> Select all {shown.length} shown
            </label>
          ) : null}
        </PBody>
      </Panel>
      {canWrite ? (
        <ImportBox title="Combination upload" path="/api/v1/jupeb/office/combinations/import" onDone={() => setTick((t) => t + 1)}
          aliases={{ "code": "code", "combination code": "code", "name": "name", "combination": "name", "combination name": "name", "subject 1": "subject1", "subject1": "subject1",
            "first subject": "subject1", "subject 2": "subject2", "subject2": "subject2", "second subject": "subject2", "subject 3": "subject3", "subject3": "subject3", "third subject": "subject3",
            "area": "area", "faculty area": "area", "faculties": "faculties", "relevant faculties": "faculties", "programmes": "programmes", "relevant programmes": "programmes",
            "description": "description", "eligibility": "eligibility", "eligibility notes": "eligibility", "active": "active", "status": "active" }}
          template={[["S/N", "Code", "Name", "Subject 1", "Subject 2", "Subject 3", "Area", "Faculties", "Programmes", "Description", "Eligibility Notes", "Active"], [[1, "", "", "", "", "", "Science", "", "", "", "", "Yes"]]]}
          describe={<>One row per combination. Subjects are matched by code or title; a subject not yet on the list is named in the preview and added on commit. A combination applicants hold keeps its subjects.</>}
          columns={["Code", "Name", "Subjects"]} cells={(r) => [String(r.code ?? ""), String(r.name ?? ""), Array.isArray(r.subjects) ? (r.subjects as string[]).join(" / ") : ""]} />
      ) : null}
      <Panel title={`Subjects (${subjects.length})`} right={canWrite ? <Btn kind="secondary" onClick={() => setSub({ code: "", title: "", description: "", active: "yes" })}>Add subject</Btn> : null}>
        <PBody>
          <p className="sub2">Disabling a subject stops every combination that contains it from being offered.</p>
          <DTable pageSize={50} cols={["Code", "Title", "Combinations|num", "Status", ...(canWrite ? ["|mid"] : [])]} texts={subjects.map((s) => `${s.code} ${s.title}`)}
            rows={subjects.map((s) => [<b key="c">{s.code}</b>, s.title, s.combinations, s.active ? <Pil key="a" kind="ok">Offered</Pil> : <Pil key="a" kind="grey">Disabled</Pil>,
              ...(canWrite ? [<span key="e" className="row" style={{ gap: "var(--s-1)", justifyContent: "center", flexWrap: "nowrap" }}>
                {s.active ? <Btn kind="ghost" onClick={() => setAsk({ kind: "subjects", codes: [s.code], offered: false, what: `${s.title} (${s.code})` })}>Disable</Btn>
                  : <Btn kind="ghost" onClick={() => setAsk({ kind: "subjects", codes: [s.code], offered: true, what: `${s.title} (${s.code})` })}>Reactivate</Btn>}
                <Btn kind="ghost" onClick={() => setSub({ code: s.code, title: s.title, description: s.description ?? "", active: s.active ? "yes" : "no" })}>Edit</Btn>
              </span>] : [])])} />
        </PBody>
      </Panel>
      {ask ? (
        <Modal title={ask.offered ? `Reactivate ${ask.what}` : `Disable ${ask.what}`} onClose={() => setAsk(null)}
          foot={<><Btn kind="ghost" onClick={() => setAsk(null)}>Cancel</Btn><Btn kind="primary" disabled={busy} onClick={() => void setOffered()}>{busy ? "Saving…" : ask.offered ? "Reactivate" : "Disable"}</Btn></>}>
          <p>{ask.offered
            ? "Applicants and students will again be able to choose it (a combination is offered only while its three subjects are offered too)."
            : ask.kind === "subjects"
              ? "Every combination containing this subject stops being offered. Nothing is deleted; subjects already registered are kept. A candidate holding an affected combination who has not registered is told to choose another."
              : "It stops being offered. Nothing is deleted; subjects already registered are kept. A candidate holding it who has not registered is told to choose another."}</p>
          <Field id="o-reason" label="Reason (kept on the record)"><input id="o-reason" className="ctl" maxLength={500} value={reason} onChange={(e) => setReason(e.target.value)} placeholder={ask.offered ? "e.g. a lecturer is now available" : "e.g. not offered by the University this session"} /></Field>
        </Modal>
      ) : null}
      {sub ? (
        <Modal title="Subject" onClose={() => setSub(null)} foot={<><Btn kind="ghost" onClick={() => setSub(null)}>Cancel</Btn><Btn kind="primary" onClick={() => void saveSubject()}>Save</Btn></>}>
          <Field id="s-code" label="Code"><input id="s-code" className="ctl" maxLength={40} value={sub.code} onChange={(e) => setSub({ ...sub, code: e.target.value.toUpperCase() })} /></Field>
          <Field id="s-title" label="Title"><input id="s-title" className="ctl" maxLength={160} value={sub.title} onChange={(e) => setSub({ ...sub, title: e.target.value })} /></Field>
          <Field id="s-desc" label="Description"><input id="s-desc" className="ctl" maxLength={600} value={sub.description} onChange={(e) => setSub({ ...sub, description: e.target.value })} /></Field>
          <Field id="s-act" label="Offered"><select id="s-act" className="ctl" value={sub.active} onChange={(e) => setSub({ ...sub, active: e.target.value })}><option value="yes">Yes</option><option value="no">No</option></select></Field>
          {canWrite && subjects.some((s) => s.code === sub.code) ? <SubjectUnits code={sub.code} /> : null}
        </Modal>
      ) : null}
      {comb ? (
        <Modal wide title="Combination" onClose={() => setComb(null)} foot={<><Btn kind="ghost" onClick={() => setComb(null)}>Cancel</Btn><Btn kind="primary" onClick={() => void saveComb()}>Save</Btn></>}>
          <div className="grid grid--2">
            <Field id="c-code" label="Code"><input id="c-code" className="ctl" maxLength={20} value={comb.code} onChange={(e) => setComb({ ...comb, code: e.target.value.toUpperCase() })} /></Field>
            <Field id="c-name" label="Name"><input id="c-name" className="ctl" maxLength={160} value={comb.name} onChange={(e) => setComb({ ...comb, name: e.target.value })} /></Field>
            {(["subject1", "subject2", "subject3"] as const).map((k, i) => (
              <Field key={k} id={`c-${k}`} label={`Subject ${i + 1}`}><select id={`c-${k}`} className="ctl" value={comb[k]} onChange={(e) => setComb({ ...comb, [k]: e.target.value })}>
                <option value="">—</option>{subjects.filter((s) => s.active || s.code === comb[k]).map((s) => <option key={s.code} value={s.code}>{s.title} ({s.code})</option>)}</select></Field>
            ))}
            <Field id="c-area" label="Area" hint="Science and Engineering suit Science applicants; every other area suits Non-Science"><select id="c-area" className="ctl" value={comb.area} onChange={(e) => setComb({ ...comb, area: e.target.value })}>
              <option value="">—</option>{["Arts", "Law", "Engineering", "Science", "Social Sciences", "Management Sciences", "Other"].map((a) => <option key={a}>{a}</option>)}</select></Field>
            <Field id="c-fac" label="Leads to faculties" hint="Codes or names, separated by commas; blank keeps what is recorded"><input id="c-fac" className="ctl" value={comb.faculties} onChange={(e) => setComb({ ...comb, faculties: e.target.value })} /></Field>
            <Field id="c-prog" label="Leads to programmes" hint="Codes or names, separated by commas"><input id="c-prog" className="ctl" value={comb.programmes} onChange={(e) => setComb({ ...comb, programmes: e.target.value })} /></Field>
            <Field id="c-desc" label="Description"><input id="c-desc" className="ctl" value={comb.description} onChange={(e) => setComb({ ...comb, description: e.target.value })} /></Field>
            <Field id="c-elig" label="Eligibility notes"><input id="c-elig" className="ctl" value={comb.eligibility} onChange={(e) => setComb({ ...comb, eligibility: e.target.value })} /></Field>
            <Field id="c-act" label="Offered"><select id="c-act" className="ctl" value={comb.active} onChange={(e) => setComb({ ...comb, active: e.target.value })}><option value="yes">Yes</option><option value="no">No</option></select></Field>
          </div>
        </Modal>
      ) : null}
    </>
  );
}

/** a subject's course units (BIO 001 …), printed in the note of the statement of result (V342) */
function SubjectUnits({ code }: { code: string }) {
  const [units, setUnits] = useState<{ code: string; title: string }[] | null>(null);
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    let live = true;
    void jcall<{ code: string; title: string }[]>(`/api/v1/jupeb/office/subjects/${encodeURIComponent(code)}/units`).then((r) => { if (live) setUnits(r.ok ? r.data : []); });
    return () => { live = false; };
  }, [code]);
  if (!units) return null;
  const list = units;
  async function save() {
    setBusy(true);
    try {
      const r = await jcall<{ code: string; title: string }[]>(`/api/v1/jupeb/office/subjects/${encodeURIComponent(code)}/units`, "PUT",
        { units: list.filter((u) => u.code.trim() || u.title.trim()) }, "JUPEB course units saved");
      if (!r.ok) { notifyProblem(r.problem); return; }
      setUnits(r.data); notify("Course units saved.");
    } finally { setBusy(false); }
  }
  return (
    <div className="mt-3">
      <div className="eyebrow">Course units (printed on the statement of result)</div>
      {list.map((u, i) => (
        <div key={i} className="row" style={{ gap: "var(--s-2)", marginTop: "var(--s-1)" }}>
          <input className="ctl" style={{ width: 110 }} aria-label={`Unit ${i + 1} code`} placeholder="BIO 001" maxLength={9} value={u.code} onChange={(e) => setUnits(list.map((x, j) => (j === i ? { ...x, code: e.target.value.toUpperCase() } : x)))} />
          <input className="ctl grow" aria-label={`Unit ${i + 1} title`} placeholder="General Biology" maxLength={160} value={u.title} onChange={(e) => setUnits(list.map((x, j) => (j === i ? { ...x, title: e.target.value } : x)))} />
          <Btn kind="ghost" aria-label="Remove unit" onClick={() => setUnits(list.filter((_, j) => j !== i))}>&times;</Btn>
        </div>
      ))}
      <div className="row mt-2">
        {list.length < 12 ? <Btn kind="ghost" onClick={() => setUnits([...list, { code: "", title: "" }])}>Add a unit</Btn> : null}
        <Btn kind="secondary" disabled={busy} onClick={() => void save()}>{busy ? "Saving…" : "Save units"}</Btn>
      </div>
    </div>
  );
}

/* ── classes ──────────────────────────────────────────────────────────────────────────────────── */

export function JupebClasses({ canWrite }: { canWrite: boolean }) {
  const [session, setSession] = useState("");
  const [sessions, setSessions] = useState<SessionRow[]>([]);
  const [rows, setRows] = useState<ClassRow[]>([]);
  const [combs, setCombs] = useState<Combination[]>([]);
  const [f, setF] = useState<Record<string, string>>({ name: "", combinationId: "", capacity: "" });
  useEffect(() => {
    let live = true;
    void jcall<Dash>("/api/v1/jupeb/office/dashboard").then((r) => { if (live && r.ok) { setSessions(r.data.sessions); setSession((s) => s || r.data.session); } });
    void jcall<Combination[]>("/api/v1/jupeb/office/combinations").then((r) => { if (live && r.ok) setCombs(r.data); });
    return () => { live = false; };
  }, []);
  useEffect(() => {
    let live = true;
    if (session) void jcall<ClassRow[]>(`/api/v1/jupeb/office/classes?session=${encodeURIComponent(session)}`).then((r) => { if (live && r.ok) setRows(r.data); });
    return () => { live = false; };
  }, [session]);
  async function add() {
    const r = await jcall<ClassRow[]>("/api/v1/jupeb/office/classes", "POST", { session, name: f.name, combinationId: f.combinationId || null, capacity: f.capacity ? Number(f.capacity) : null }, "JUPEB class added");
    if (!r.ok) { notifyProblem(r.problem); return; }
    setRows(r.data); setF({ name: "", combinationId: "", capacity: "" });
  }
  return (
    <>
      <PageHead title="JUPEB classes" description="Sets of students for teaching. A student is placed in a class from their record." actions={<SessionPick sessions={sessions} value={session} onChange={setSession} />} />
      {canWrite ? (
        <Panel title="Add a class">
          <PBody><div className="grid grid--4">
            <Field id="k-name" label="Name"><input id="k-name" className="ctl" maxLength={80} value={f.name} onChange={(e) => setF({ ...f, name: e.target.value })} /></Field>
            <Field id="k-comb" label="Combination (optional)"><select id="k-comb" className="ctl" value={f.combinationId} onChange={(e) => setF({ ...f, combinationId: e.target.value })}>
              <option value="">Any</option>{combs.map((c) => <option key={c.id} value={c.id}>{c.code}</option>)}</select></Field>
            <Field id="k-cap" label="Capacity"><input id="k-cap" className="ctl tnum" inputMode="numeric" value={f.capacity} onChange={(e) => setF({ ...f, capacity: e.target.value.replace(/\D/g, "") })} /></Field>
            <div className="field"><label>&nbsp;</label><Btn kind="primary" disabled={!f.name.trim()} onClick={() => void add()}>Add class</Btn></div>
          </div></PBody>
        </Panel>
      ) : null}
      <Panel title={`Classes — ${session}`}>
        <PBody><DTable pageSize={50} cols={["Name", "Combination", "Members|num", "Capacity|num"]} rows={rows.map((k) => [k.name, k.combination_code ?? "Any", k.members, k.capacity ?? "—"])} /></PBody>
      </Panel>
    </>
  );
}

/* ── settings ─────────────────────────────────────────────────────────────────────────────────── */

interface Settings {
  session: string; sessions: SessionRow[]; own: boolean;
  setting: { application_prefix: string; screening_required: boolean; screening_venue: string | null; screening_starts_on: string | null; screening_ends_on: string | null; screening_instructions: string | null; results_published_at: string | null; exam_month: string | null };
  documentKinds: { code: string; label: string; required: boolean; image: boolean; active: boolean; ord: number }[];
  fees: { application_fee: number; checking_fee: number; acceptance_fee: number; first_percent: number; allow_full: boolean; activation: string; indigene_state: string };
}

export function JupebSettings({ canWrite }: { canWrite: boolean }) {
  const [session, setSession] = useState("");
  const [s, setS] = useState<Settings | null>(null);
  const [f, setF] = useState<Record<string, string>>({});
  const [doc, setDoc] = useState<Record<string, string> | null>(null);
  const [scope, setScope] = useState<"session" | "default">("session");
  useEffect(() => {
    let live = true;
    void jcall<Settings>(`/api/v1/jupeb/office/settings${session ? `?session=${encodeURIComponent(session)}` : ""}`).then((r) => {
      if (!live || !r.ok) return;
      setS(r.data);
      const x = r.data.setting;
      setF({ applicationPrefix: x.application_prefix, screeningRequired: x.screening_required ? "yes" : "no", screeningVenue: x.screening_venue ?? "", screeningStartsOn: x.screening_starts_on ?? "",
        screeningEndsOn: x.screening_ends_on ?? "", screeningInstructions: x.screening_instructions ?? "", examMonth: x.exam_month ?? "" });
    });
    return () => { live = false; };
  }, [session]);
  async function save() {
    if (!s) return;
    const r = await jcall<Settings>("/api/v1/jupeb/office/settings", "PUT", {
      session: scope === "default" ? "*" : s.session, applicationPrefix: f.applicationPrefix, screeningRequired: f.screeningRequired === "yes", screeningVenue: f.screeningVenue || null,
      screeningStartsOn: f.screeningStartsOn || null, screeningEndsOn: f.screeningEndsOn || null, screeningInstructions: f.screeningInstructions || null,
      examMonth: f.examMonth?.trim() || null,
    }, "JUPEB settings saved");
    if (!r.ok) { notifyProblem(r.problem); return; }
    setS(r.data); notify("Settings saved.");
  }
  async function saveDoc() {
    if (!doc) return;
    const r = await jcall<Settings>("/api/v1/jupeb/office/document-kinds", "POST", { code: doc.code, label: doc.label, required: doc.required === "yes", image: doc.image === "yes", active: doc.active === "yes", ord: doc.ord ? Number(doc.ord) : null }, "JUPEB document kind saved");
    if (!r.ok) { notifyProblem(r.problem); return; }
    setS({ ...r.data, setting: s?.setting ?? r.data.setting }); setDoc(null);
  }
  if (!s) return <Note kind="info" title="Loading…">One moment.</Note>;
  const ro = !canWrite;
  return (
    <>
      <PageHead title="JUPEB settings" description="Numbering, screening and the documents asked for. The fees are the Bursary's." actions={<SessionPick sessions={s.sessions} value={s.session} onChange={setSession} />} />
      <Panel title="Numbering and screening" right={s.own ? <Pil kind="info">Own rule for {s.session}</Pil> : <Pil kind="grey">The default applies</Pil>}>
        <PBody>
          <div className="grid grid--3">
            <Field id="st-scope" label="Save for"><select id="st-scope" className="ctl" value={scope} onChange={(e) => setScope(e.target.value as "session" | "default")} disabled={ro}><option value="session">{s.session} only</option><option value="default">Every session without its own</option></select></Field>
            <Field id="st-prefix" label="Application number prefix" hint="JUPEB/APP gives JUPEB/APP/2026/000001"><input id="st-prefix" className="ctl" value={f.applicationPrefix ?? ""} onChange={(e) => setF({ ...f, applicationPrefix: e.target.value.toUpperCase() })} disabled={ro} /></Field>
            <Field id="st-req" label="Screening required before school fees"><select id="st-req" className="ctl" value={f.screeningRequired} onChange={(e) => setF({ ...f, screeningRequired: e.target.value })} disabled={ro}><option value="no">No</option><option value="yes">Yes</option></select></Field>
            <Field id="st-venue" label="Screening venue"><input id="st-venue" className="ctl" value={f.screeningVenue ?? ""} onChange={(e) => setF({ ...f, screeningVenue: e.target.value })} disabled={ro} /></Field>
            <Field id="st-from" label="Screening from"><input id="st-from" type="date" className="ctl" value={f.screeningStartsOn ?? ""} onChange={(e) => setF({ ...f, screeningStartsOn: e.target.value })} disabled={ro} /></Field>
            <Field id="st-to" label="Screening to"><input id="st-to" type="date" className="ctl" value={f.screeningEndsOn ?? ""} onChange={(e) => setF({ ...f, screeningEndsOn: e.target.value })} disabled={ro} /></Field>
            <Field id="st-exam" label="Examination month and year" hint="Printed on the statement of result, e.g. August 2026"><input id="st-exam" className="ctl" maxLength={40} value={f.examMonth ?? ""} onChange={(e) => setF({ ...f, examMonth: e.target.value })} disabled={ro} /></Field>
          </div>
          <Field id="st-instr" label="Screening instructions"><textarea id="st-instr" className="ctl" rows={3} value={f.screeningInstructions ?? ""} onChange={(e) => setF({ ...f, screeningInstructions: e.target.value })} disabled={ro} /></Field>
          {canWrite ? <Btn kind="primary" onClick={() => void save()}>Save settings</Btn> : null}
        </PBody>
      </Panel>
      <Panel title="Documents asked for" right={canWrite ? <Btn kind="secondary" onClick={() => setDoc({ code: "", label: "", required: "yes", image: "no", active: "yes", ord: "" })}>Add document</Btn> : null}>
        <PBody><DTable noPrint pageSize={0} cols={["Code", "Document", "Required|mid", "Image|mid", "Active|mid", ...(canWrite ? ["|mid"] : [])]} rows={s.documentKinds.map((d) => [d.code, d.label, d.required ? "Yes" : "No", d.image ? "Yes" : "No", d.active ? "Yes" : "No",
          ...(canWrite ? [<Btn key="e" kind="ghost" onClick={() => setDoc({ code: d.code, label: d.label, required: d.required ? "yes" : "no", image: d.image ? "yes" : "no", active: d.active ? "yes" : "no", ord: String(d.ord) })}>Edit</Btn>] : [])])} /></PBody>
      </Panel>
      <ReminderRules canWrite={canWrite} />
      <Panel title="Fees (set by the Bursary)">
        <PBody><KvGrid pairs={[["Application fee", naira(s.fees.application_fee)], ["Admission status checking fee", naira(s.fees.checking_fee)], ["Acceptance fee", naira(s.fees.acceptance_fee)],
          ["First semester share", `${Number(s.fees.first_percent)}%`], ["Full payment", s.fees.allow_full ? "Allowed" : "Not allowed"],
          ["Activation", s.fees.activation === "FULL" ? "Full payment" : "First instalment"], ["Indigene state", s.fees.indigene_state]]} />
          <p className="sub2 mt-2">The JUPEB Office sees these amounts; only the Bursary changes them (Finance → JUPEB fees).</p></PBody>
      </Panel>
      {doc ? (
        <Modal title="Document asked for" onClose={() => setDoc(null)} foot={<><Btn kind="ghost" onClick={() => setDoc(null)}>Cancel</Btn><Btn kind="primary" onClick={() => void saveDoc()}>Save</Btn></>}>
          <Field id="d-code" label="Code"><input id="d-code" className="ctl" value={doc.code} onChange={(e) => setDoc({ ...doc, code: e.target.value.toUpperCase().replace(/[^A-Z0-9_]/g, "_") })} /></Field>
          <Field id="d-label" label="Label"><input id="d-label" className="ctl" value={doc.label} onChange={(e) => setDoc({ ...doc, label: e.target.value })} /></Field>
          <div className="grid grid--3">
            {(["required", "image", "active"] as const).map((k) => <Field key={k} id={`d-${k}`} label={k[0].toUpperCase() + k.slice(1)}><select id={`d-${k}`} className="ctl" value={doc[k]} onChange={(e) => setDoc({ ...doc, [k]: e.target.value })}><option value="yes">Yes</option><option value="no">No</option></select></Field>)}
          </div>
        </Modal>
      ) : null}
    </>
  );
}

/* ── payments (read only, for the JUPEB Office and the Bursary) ───────────────────────────────── */

interface Payment { reference: string; kind: string; amount: number; semester: number | null; created_at: string; expires_at: string; confirmed_at: string | null; channel: string | null; application_no: string; name: string; state: string; exam_no: string | null }

export function JupebPayments({ canConfirm }: { canConfirm: boolean }) {
  const [session, setSession] = useState("");
  const [sessions, setSessions] = useState<string[]>([]);
  const [status, setStatus] = useState("CONFIRMED");
  const [rows, setRows] = useState<Payment[]>([]);
  const [confirm, setConfirm] = useState<{ reference: string; channel: string; reason: string } | null>(null);
  const [tick, setTick] = useState(0);
  useEffect(() => {
    let live = true;
    void jcall<{ sessions: string[]; session: string }>("/api/v1/jupeb/fees").then((r) => { if (live && r.ok) { setSessions(r.data.sessions); setSession((s) => s || r.data.session); } });
    return () => { live = false; };
  }, []);
  useEffect(() => {
    let live = true;
    if (session) void jcall<Payment[]>(`/api/v1/jupeb/fees/payments?session=${encodeURIComponent(session)}&status=${status}`).then((r) => { if (live && r.ok) setRows(r.data); });
    return () => { live = false; };
  }, [session, status, tick]);
  async function exportAll() {
    const blob = await brandedXlsx(`JUPEB payments — ${session}`, ["Reference", "Fee", "Amount", "Application No", "Name", "Generated", "Confirmed", "Channel", "Status"],
      rows.map((p) => [p.reference, FEE_KIND[p.kind] ?? p.kind, Number(p.amount), p.application_no, p.name, day(p.created_at), day(p.confirmed_at), p.channel, STATE_SHORT[p.state] ?? p.state]),
      { sheetName: "Payments", serial: docSerial("JUPEBPAY"), meta: [["Session", session], ["Status", status || "All"]] });
    downloadBlob(blob, `jupeb-payments-${session.replace("/", "-")}.xlsx`);
  }
  async function doConfirm() {
    if (!confirm) return;
    const r = await jcall<{ outcome: string }>(`/api/v1/jupeb/fees/payments/${encodeURIComponent(confirm.reference)}/confirm`, "POST", { channel: confirm.channel, reason: confirm.reason }, `Bank payment confirmed: ${confirm.reference}`);
    if (!r.ok) { notifyProblem(r.problem); return; }
    notify(`${confirm.reference}: ${r.data.outcome}.`); setConfirm(null); setTick((t) => t + 1);
  }
  const total = rows.filter((p) => p.confirmed_at).reduce((n, p) => n + Number(p.amount), 0);
  return (
    <>
      <PageHead title="JUPEB payments" description="Application fees and school fees of the session, as the payment records stand. Amounts are the Bursary's; nothing here changes them."
        actions={<span className="row">
          <select className="ctl" aria-label="Session" style={{ width: 140 }} value={session} onChange={(e) => setSession(e.target.value)}>{sessions.map((s) => <option key={s}>{s}</option>)}</select>
          <select className="ctl" aria-label="Status" style={{ width: 140 }} value={status} onChange={(e) => setStatus(e.target.value)}><option value="CONFIRMED">Confirmed</option><option value="PENDING">Not confirmed</option><option value="">All</option></select>
          <Btn kind="ghost" onClick={() => void exportAll()}>Export (Excel)</Btn></span>} />
      <Tiles items={[["Payments", rows.length, null, status ? status.toLowerCase() : "all"], ["Confirmed amount", naira(total), null, session]]} cls="grid--2" />
      <Panel title="Payments">
        <PBody><DTable pageSize={50} cols={["Reference", "Fee", "Amount|num", "Application No", "Name", "Confirmed", ...(canConfirm ? ["|mid"] : [])]} texts={rows.map((p) => `${p.reference} ${p.application_no} ${p.name}`)}
          rows={rows.map((p) => [p.reference, FEE_KIND[p.kind] ?? p.kind, naira(p.amount), p.application_no, p.name, p.confirmed_at ? `${day(p.confirmed_at)} · ${p.channel ?? ""}` : "—",
            ...(canConfirm ? [p.confirmed_at ? "" : <Btn key="c" kind="ghost" onClick={() => setConfirm({ reference: p.reference, channel: "Bank teller", reason: "" })}>Confirm bank payment…</Btn>] : [])])} /></PBody>
      </Panel>
      {confirm ? (
        <Modal title={`Confirm ${confirm.reference}`} sub="A payment made at the bank, seen on the teller" onClose={() => setConfirm(null)}
          foot={<><Btn kind="ghost" onClick={() => setConfirm(null)}>Cancel</Btn><Btn kind="go" disabled={!confirm.reason.trim()} onClick={() => void doConfirm()}>Confirm</Btn></>}>
          <Field id="p-ch" label="Channel"><input id="p-ch" className="ctl" value={confirm.channel} onChange={(e) => setConfirm({ ...confirm, channel: e.target.value })} /></Field>
          <Field id="p-re" label="Teller and reason" required><textarea id="p-re" className="ctl" rows={3} value={confirm.reason} onChange={(e) => setConfirm({ ...confirm, reason: e.target.value })} /></Field>
        </Modal>
      ) : null}
    </>
  );
}
