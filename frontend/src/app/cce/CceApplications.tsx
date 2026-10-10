"use client";

/**
 * The CCE applications (V379): the list and the queue of admission processing; one application read whole — what the CCE list
 * gave, the form, the O'Level by sitting with the compulsory credits, the documents (viewed, accepted or rejected with the reason
 * the applicant reads), the payments, the history — and the review's next step for the acting office: the Centre takes it up,
 * asks for documents or verification, recommends; someone other than the recommender approves; the Academic Office publishes.
 * The admission list, and the CCE students on the register.
 */
import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, LinkBtn, Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import { buildXlsx } from "@/lib/xlsx";
import { downloadBlob } from "@/lib/exportbrand";
import type { Problem } from "@/lib/api";
import {
  ACTION_LABEL, DOC_LABEL, PROCESSING_STATES, REVIEW_LABEL, REVIEW_STATES, ccall, day, labelOf, naira, when,
  type AppDetail, type AppRow, type DeskDoc, type Paged, type StudentRow,
} from "@/lib/cce";
import { cceSend, type Powers } from "./CceDesk";
import { Pager, type TabProps } from "./CceList";

/* ── the list, and the processing queue ─────────────────────────────────────────────────────────────────────────── */

export function CceApplications({ session, pick, processing, initialState }: TabProps & { processing?: boolean; initialState?: string | null }) {
  const [state, setState] = useState(initialState ?? (processing ? PROCESSING_STATES.join(",") : ""));
  const [q, setQ] = useState("");
  const [query, setQuery] = useState("");
  const [page, setPage] = useState(0);
  const [data, setData] = useState<Paged<AppRow> | null>(null);
  useEffect(() => {
    let live = true;
    void ccall<Paged<AppRow>>(`/api/v1/cce/applications?session=${encodeURIComponent(session)}&state=${encodeURIComponent(state)}&q=${encodeURIComponent(query)}&page=${page}&size=50`)
      .then((r) => { if (!live) return; if (r.ok) setData(r.data); else notifyProblem(r.problem); });
    return () => { live = false; };
  }, [session, state, query, page]);
  const states = processing ? PROCESSING_STATES : REVIEW_STATES;
  return (
    <>
      <PageHead title={processing ? "Admission processing" : "CCE applications"}
        description={processing ? `${session} · oldest submission first` : session} actions={pick} />
      <Panel title={processing ? "To act on" : "Applications"} right={<span className="row row--inline row--tight">
        <form onSubmit={(e) => { e.preventDefault(); setQuery(q.trim()); setPage(0); }}><input className="ctl" style={{ width: 230 }} placeholder="JAMB, application no, name, phone…" aria-label="Search the applications" value={q} onChange={(e) => setQ(e.target.value)} /></form>
        <select className="ctl" aria-label="State" value={state} onChange={(e) => { setState(e.target.value); setPage(0); }}>
          <option value={processing ? PROCESSING_STATES.join(",") : ""}>{processing ? "Everything to act on" : "Every state"}</option>
          {states.map((s) => <option key={s} value={s}>{REVIEW_LABEL[s][0]}</option>)}
        </select>
      </span>}>
        {data === null ? <PBody><div className="sub2">Reading…</div></PBody> : data.rows.length ? (
          <>
            <DTable pageSize={0} cols={["Application", "Name", "Programme", "State", "Submitted", "Documents to check|num"]} rows={data.rows.map((a) => [
              <Link key="a" href={`/cce/applications/${a.id}`} className="tnum">{a.application_no}<div className="sub2">{a.jamb_reg_no}</div></Link>,
              <span key="n">{a.name}<div className="sub2">{[a.phone, a.email].filter(Boolean).join(" · ")}</div></span>,
              <span key="p">{a.programme}<div className="sub2">{a.department ?? ""}</div></span>,
              <Pil key="s" kind={labelOf(REVIEW_LABEL, a.state)[1]}>{labelOf(REVIEW_LABEL, a.state)[0]}</Pil>,
              <span key="d">{a.submitted_at ? when(a.submitted_at) : <span className="sub2">not yet</span>}</span>,
              a.documents_pending,
            ])} />
            <Pager total={data.total} page={page} size={data.size} onPage={setPage} />
          </>
        ) : <PBody><div className="sub2">{processing ? "Nothing waits to be acted on." : "No CCE application yet for this session."}</div></PBody>}
      </Panel>
    </>
  );
}

/* ── one application ────────────────────────────────────────────────────────────────────────────────────────────── */

type Step = { action: string; label: string; kind: "primary" | "secondary" | "ghost" | "go" | "urgent"; note: "required" | "optional" | "none"; who: "centre" | "decide" };
const STEPS: Record<string, Step[]> = {
  SUBMITTED: [{ action: "START", label: "Take it up for review", kind: "primary", note: "none", who: "centre" }],
  UNDER_REVIEW: [
    { action: "RECOMMEND", label: "Recommend admission", kind: "go", note: "optional", who: "centre" },
    { action: "REQUEST_DOCUMENTS", label: "Ask for documents", kind: "secondary", note: "required", who: "centre" },
    { action: "REQUIRE_VERIFICATION", label: "Ask for verification", kind: "secondary", note: "required", who: "centre" },
  ],
  DOCUMENTS_PENDING: [{ action: "RESUME", label: "Take it back under review", kind: "secondary", note: "none", who: "centre" }],
  VERIFICATION_REQUIRED: [{ action: "RESUME", label: "Take it back under review", kind: "secondary", note: "none", who: "centre" }],
  RECOMMENDED: [
    { action: "APPROVE", label: "Approve admission", kind: "go", note: "optional", who: "decide" },
    { action: "REQUEST_DOCUMENTS", label: "Ask for documents", kind: "secondary", note: "required", who: "centre" },
  ],
  APPROVED: [{ action: "REOPEN", label: "Reopen the decision", kind: "ghost", note: "required", who: "decide" }],
  NOT_ADMITTED: [{ action: "REOPEN", label: "Reopen the decision", kind: "ghost", note: "required", who: "decide" }],
  REJECTED: [{ action: "REOPEN", label: "Reopen the decision", kind: "ghost", note: "required", who: "decide" }],
};
const DECLINABLE = new Set(["SUBMITTED", "UNDER_REVIEW", "DOCUMENTS_PENDING", "VERIFICATION_REQUIRED", "RECOMMENDED", "APPROVED"]);
const NOTE_LABEL: Record<string, string> = {
  REQUEST_DOCUMENTS: "What the applicant is to provide (they read this)", REQUIRE_VERIFICATION: "What is to be verified, and how (they read this)",
  RECOMMEND: "The recommendation (optional)", APPROVE: "A note on the approval (optional)", NOT_ADMIT: "Why not (the applicant reads this)",
  REJECT: "Why the application is rejected (the applicant reads this)", REOPEN: "Why the decision is reopened",
};
const FIELD_LABEL: Record<string, string> = {
  date_of_birth: "Date of birth", place_of_birth: "Place of birth", marital_status: "Marital status", religion: "Religion", home_address: "Home address",
  postal_address: "Postal address", state_of_origin: "State of origin", lga: "LGA", nationality: "Nationality", mobile: "Mobile", alt_mobile: "Alternative number",
  personal_email: "Email", employer: "Employer", disability: "Disability or access need", kin_name: "Next of kin", kin_relationship: "Relationship",
  kin_mobile: "Next of kin's mobile", kin_address: "Next of kin's address",
};

export function CceApplication({ id, powers }: { id: string; powers: Powers }) {
  const [a, setA] = useState<AppDetail | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [step, setStep] = useState<Step | null>(null);
  const [note, setNote] = useState("");
  const [busy, setBusy] = useState(false);
  const [viewing, setViewing] = useState<{ doc: DeskDoc; url: string } | null>(null);
  const [rejecting, setRejecting] = useState<DeskDoc | null>(null);
  useEffect(() => {
    let live = true;
    void ccall<AppDetail>(`/api/v1/cce/applications/${id}`).then((r) => { if (!live) return; if (r.ok) setA(r.data); else setProblem(r.problem); });
    return () => { live = false; };
  }, [id]);
  if (problem) return <ProblemNotice problem={problem} />;
  if (!a) return <Note kind="info" title="Reading the application…">One moment.</Note>;
  const r = a.review;
  const published = !!r.published_at;
  const allowed = (s: Step) => (s.who === "centre" ? powers.centre : powers.decide);
  const steps = published ? [] : (STEPS[r.state] ?? []).filter(allowed);
  const ownRecommendation = r.state === "RECOMMENDED" && !!a.me && r.recommended_by === a.me;

  async function act(s: Step) {
    setBusy(true);
    try {
      const out = await cceSend<AppDetail>(`/applications/${id}/act`, "POST", { action: s.action, note: note.trim() || null }, `${ACTION_LABEL[s.action] ?? s.action}: CCE application ${a?.application_no}`);
      if (out) { setA(out); setStep(null); setNote(""); }
    } finally { setBusy(false); }
  }
  async function review(doc: DeskDoc, status: "ACCEPTED" | "REJECTED", why?: string) {
    setBusy(true);
    try {
      const out = await cceSend<AppDetail>(`/applications/${id}/documents/${doc.id}/review`, "POST", { status, note: why ?? null }, `${DOC_LABEL[doc.kind] ?? doc.kind} ${status === "ACCEPTED" ? "accepted" : "rejected"}: ${a?.application_no}`);
      if (out) { setA(out); setRejecting(null); setNote(""); }
    } finally { setBusy(false); }
  }
  async function view(doc: DeskDoc) {
    const res = await fetch(`/api/bff/api/v1/cce/applications/${id}/documents/${doc.id}`);
    if (!res.ok) { notifyProblem({ status: res.status, title: "The document could not be opened" }); return; }
    setViewing({ doc, url: URL.createObjectURL(await res.blob()) });
  }

  const sittings = [1, 2].map((n) => a.olevel.filter((o) => o.sitting === n)).filter((x) => x.length);
  const bio = new Map(a.biodata.map((b) => [b.field, b.value]));
  const reviewable = ["SUBMITTED", "UNDER_REVIEW", "DOCUMENTS_PENDING", "VERIFICATION_REQUIRED", "RECOMMENDED"].includes(r.state) && !published;

  return (
    <>
      <PageHead title={`${a.name} · ${a.application_no}`} description={`${a.programme} · JAMB ${a.jamb_reg_no} · CCE ${a.listed.session}`}
        actions={<LinkBtn kind="ghost" href={`/cce/applications?session=${encodeURIComponent(a.listed.session)}`}>← The applications</LinkBtn>} />
      <Tiles cls="grid--4" items={[
        ["STATE", labelOf(REVIEW_LABEL, r.state)[0], null, published ? `published ${day(r.published_at)}` : r.state === "DRAFT" ? "the applicant is completing it" : "not yet published"],
        ["APPLICATION FEE", a.fee_confirmed_at ? "Paid" : "Unpaid", a.fee_confirmed_at ? "var(--green-ink)" : "var(--amber-ink)", a.fee_confirmed_at ? when(a.fee_confirmed_at) : "the form is submitted once it is paid"],
        ["DOCUMENTS", `${a.documents.filter((d) => d.status === "ACCEPTED").length} of ${a.documents.length} accepted`, a.documents.some((d) => d.status === "REJECTED") ? "var(--red-ink)" : null, `${a.documents.filter((d) => d.status === "PENDING").length} to check`],
        ["ADMISSION", a.admission_no ?? (a.accepted_at ? "Accepted" : "—"), null, a.matric_no ?? (a.accepted_at ? `accepted ${day(a.accepted_at)}` : "")],
      ]} />
      {r.request_note && ["DOCUMENTS_PENDING", "VERIFICATION_REQUIRED"].includes(r.state) ? <Note kind="info" title="Asked of the applicant">{r.request_note}</Note> : null}
      {r.decision_note && ["APPROVED", "ADMITTED", "NOT_ADMITTED", "REJECTED"].includes(r.state) ? <Note kind={r.state === "NOT_ADMITTED" || r.state === "REJECTED" ? "bad" : "ok"} title={`${labelOf(REVIEW_LABEL, r.state)[0]} — ${r.decided_by_name ?? ""} (${r.decided_office ?? ""})`}>{r.decision_note}</Note> : null}
      {r.recommended_at ? <div className="sub2 mb-2">Recommended {when(r.recommended_at)} by {r.recommended_by_name ?? "—"}{r.recommendation_note ? `: ${r.recommendation_note}` : ""}</div> : null}
      {a.problems.length && r.state === "DRAFT" ? <Note kind="info" title="The applicant still has to">{a.problems.map((p) => p.message).join("; ")}.</Note> : null}

      {steps.length || (!published && DECLINABLE.has(r.state) && powers.decide) ? (
        <Panel title="The next step">
          <PBody>
            <div className="row row--inline" style={{ flexWrap: "wrap" }}>
              {steps.map((s) => (
                <Btn key={s.action} kind={s.kind} disabled={busy || (s.action === "APPROVE" && ownRecommendation)} title={s.action === "APPROVE" && ownRecommendation ? "You recommended it; someone else approves" : undefined}
                  onClick={() => { if (s.note === "none") void act(s); else { setStep(s); setNote(""); } }}>{s.label}</Btn>
              ))}
              {!published && DECLINABLE.has(r.state) && powers.decide ? (
                <>
                  <Btn kind="ghost" disabled={busy} onClick={() => { setStep({ action: "NOT_ADMIT", label: "Not admit", kind: "urgent", note: "required", who: "decide" }); setNote(""); }}>Not admit</Btn>
                  <Btn kind="ghost" disabled={busy} onClick={() => { setStep({ action: "REJECT", label: "Reject the application", kind: "urgent", note: "required", who: "decide" }); setNote(""); }}>Reject</Btn>
                </>
              ) : null}
            </div>
            {ownRecommendation ? <div className="sub2 mt-1">You recommended this admission; someone else approves it.</div> : null}
            {r.state === "APPROVED" ? <div className="sub2 mt-1">Approved: it is published with the admission list by the Academic Office.</div> : null}
          </PBody>
        </Panel>
      ) : null}

      <div className="grid grid--2">
        <Panel title="From the CCE list" right={<span className="sub2">{a.listed.list_file}{a.listed.listed_at ? ` · committed ${day(a.listed.listed_at)}` : ""}</span>}>
          <PBody>
            <KvGrid cls="grid--2" pairs={[
              ["JAMB number", <span key="j" className="tnum">{a.listed.jamb_reg_no}</span>], ["Name", `${a.listed.surname}, ${a.listed.first_name}${a.listed.middle_name ? " " + a.listed.middle_name : ""}`],
              ["Date of birth", day(a.listed.date_of_birth)], ["Sex", a.listed.sex ?? "—"], ["State, LGA", [a.listed.state_of_origin, a.listed.lga].filter(Boolean).join(", ") || "—"],
              ["Programme", `${a.programme} (${a.programme_code})`], ["O'Level on the list", a.listed.olevel_note ?? "—"], ["Remarks", a.listed.remarks ?? "—"],
            ]} />
          </PBody>
        </Panel>
        <Panel title="The form">
          <PBody>
            <KvGrid cls="grid--2" pairs={Object.keys(FIELD_LABEL).filter((f) => bio.has(f)).map((f) => [FIELD_LABEL[f], f === "date_of_birth" ? day(bio.get(f)) : bio.get(f)] as [string, string])} />
            <div className="sub2 mt-1">Account: {a.email} · {a.phone}{r.programme_confirmed_at ? ` · programme confirmed ${day(r.programme_confirmed_at)}` : " · programme not yet confirmed"}</div>
          </PBody>
        </Panel>
      </div>

      <Panel title="O'Level" right={a.compulsory.map((c) => <Pil key={c.subject} kind={c.credit ? "ok" : "bad"} className="ml-1">{c.subject}: {c.credit ? "credit" : "no credit"}</Pil>)}>
        {sittings.length ? (
          <div className={`grid grid--${sittings.length === 2 ? "2" : "3"}`} style={{ padding: 12 }}>
            {sittings.map((rows, i) => (
              <div key={i}>
                <b>Sitting {rows[0].sitting}</b> · {rows[0].exam_body} {rows[0].exam_year} · <span className="tnum">{rows[0].exam_number}</span>
                <DTable noPrint pageSize={0} cols={["Subject", "Grade|mid"]} rows={rows.map((o) => [o.subject, <b key="g" className="tnum">{o.grade}</b>])} />
              </div>
            ))}
          </div>
        ) : <PBody><div className="sub2">No O&rsquo;Level given yet.</div></PBody>}
      </Panel>

      <Panel title="Documents">
        {a.documents.length ? (
          <DTable noPrint pageSize={0} cols={["Document", "File", "Uploaded", "Status", ""]} rows={a.documents.map((d) => [
            <b key="k">{DOC_LABEL[d.kind] ?? d.kind}</b>,
            <span key="f" className="sub2">{d.filename} · {Math.round(d.bytes / 1024)} KB</span>,
            <span key="u">{when(d.uploaded_at)}</span>,
            <span key="s"><Pil kind={d.status === "ACCEPTED" ? "ok" : d.status === "REJECTED" ? "bad" : "warn"}>{d.status === "PENDING" ? "To check" : d.status === "ACCEPTED" ? "Accepted" : "Rejected"}</Pil>{d.review_note ? <div className="sub2">{d.review_note}</div> : null}{d.reviewed_by_name ? <div className="sub2">{d.reviewed_by_name}</div> : null}</span>,
            <span key="x" className="row row--inline row--tight">
              <Btn kind="ghost" onClick={() => void view(d)}>View</Btn>
              {reviewable && powers.centre && d.status !== "ACCEPTED" ? <Btn kind="secondary" disabled={busy} onClick={() => void review(d, "ACCEPTED")}>Accept</Btn> : null}
              {reviewable && powers.centre && d.status !== "REJECTED" ? <Btn kind="ghost" disabled={busy} onClick={() => { setRejecting(d); setNote(""); }}>Reject</Btn> : null}
            </span>,
          ])} />
        ) : <PBody><div className="sub2">No document uploaded yet.</div></PBody>}
      </Panel>

      <div className="grid grid--2">
        <Panel title="Payments">
          {a.payments.length ? <DTable noPrint pageSize={0} cols={["Fee", "Reference", "Amount|num", "Confirmed"]} rows={a.payments.map((p) => [
            p.kind === "APPLICATION" ? "CCE application" : p.kind === "ACCEPTANCE" ? "CCE acceptance" : p.kind, <span key="r" className="tnum">{p.reference}</span>, naira(p.amount),
            p.confirmed_at ? <span key="c">{when(p.confirmed_at)}<div className="sub2">{p.receipt_no} · {p.channel}</div></span> : <span key="c" className="sub2">not paid</span>,
          ])} /> : <PBody><div className="sub2">No payment reference yet.</div></PBody>}
        </Panel>
        <Panel title="History">
          <DTable noPrint pageSize={0} cols={["When", "What", "Who"]} rows={a.events.map((e) => [
            <span key="w" className="tnum">{when(e.at)}</span>,
            <span key="a">{ACTION_LABEL[e.action] ?? e.action}{e.note ? <div className="sub2">{e.note}</div> : null}</span>,
            <span key="o" className="sub2">{e.actor_name ?? "—"}{e.office ? ` · ${e.office}` : ""}</span>,
          ])} />
        </Panel>
      </div>

      {step ? (
        <Modal title={step.label} sub={`${a.name} · ${a.application_no}`} onClose={() => setStep(null)}
          foot={<span className="row row--inline row--tight"><Btn kind="ghost" onClick={() => setStep(null)}>Back</Btn>
            <Btn kind={step.kind === "ghost" ? "primary" : step.kind} disabled={busy || (step.note === "required" && !note.trim())} onClick={() => void act(step)}>{step.label}</Btn></span>}>
          {step.action === "RECOMMEND" && a.compulsory.some((c) => !c.credit) ? <Note kind="bad" title="A compulsory credit is missing">{a.compulsory.filter((c) => !c.credit).map((c) => c.subject).join(", ")}: the server refuses the recommendation.</Note> : null}
          {step.action === "RECOMMEND" && a.documents.some((d) => d.status !== "ACCEPTED") ? <Note kind="bad" title="Every document is verified first">Accept or reject each document; a rejected one is replaced by the applicant.</Note> : null}
          <Field id="cce-step-note" label={NOTE_LABEL[step.action] ?? "Note"} required={step.note === "required"}><textarea id="cce-step-note" className="ctl" rows={4} value={note} onChange={(e) => setNote(e.target.value)} /></Field>
        </Modal>
      ) : null}
      {rejecting ? (
        <Modal title="Reject the document" sub={DOC_LABEL[rejecting.kind] ?? rejecting.kind} onClose={() => setRejecting(null)}
          foot={<span className="row row--inline row--tight"><Btn kind="ghost" onClick={() => setRejecting(null)}>Back</Btn><Btn kind="urgent" disabled={busy || !note.trim()} onClick={() => void review(rejecting, "REJECTED", note.trim())}>Reject</Btn></span>}>
          <Field id="cce-doc-note" label="Why (the applicant reads this and replaces it)" required><textarea id="cce-doc-note" className="ctl" rows={3} value={note} onChange={(e) => setNote(e.target.value)} /></Field>
          <div className="sub2">Rejecting a document does not send the application back: ask for documents for that.</div>
        </Modal>
      ) : null}
      {viewing ? (
        <Modal viewer title={DOC_LABEL[viewing.doc.kind] ?? viewing.doc.kind} sub={viewing.doc.filename} onClose={() => { URL.revokeObjectURL(viewing.url); setViewing(null); }}>
          {viewing.doc.content_type === "application/pdf"
            ? <iframe title={viewing.doc.filename} src={viewing.url} style={{ width: "100%", height: "78vh", border: 0 }} />
            // eslint-disable-next-line @next/next/no-img-element
            : <img src={viewing.url} alt={viewing.doc.filename} style={{ maxWidth: "100%", maxHeight: "78vh", display: "block", margin: "0 auto" }} />}
        </Modal>
      ) : null}
    </>
  );
}

/* ── the admission list ─────────────────────────────────────────────────────────────────────────────────────────── */

export function CceAdmissionList({ session, powers, pick, refresh }: TabProps) {
  const [rows, setRows] = useState<AppRow[] | null>(null);
  const [tick, setTick] = useState(0);
  const [chosen, setChosen] = useState<string[]>([]);
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    let live = true;
    void ccall<{ rows: AppRow[] }>(`/api/v1/cce/admission-list?session=${encodeURIComponent(session)}`).then((r) => { if (!live) return; if (r.ok) setRows(r.data.rows); else notifyProblem(r.problem); });
    return () => { live = false; };
  }, [session, tick]);
  const waiting = useMemo(() => (rows ?? []).filter((r) => !r.published_at), [rows]);
  const admitted = useMemo(() => (rows ?? []).filter((r) => r.state === "ADMITTED"), [rows]);
  const declined = useMemo(() => (rows ?? []).filter((r) => (r.state === "NOT_ADMITTED" || r.state === "REJECTED") && r.published_at), [rows]);
  if (rows === null) return <Note kind="info" title="Reading the admission list…">One moment.</Note>;

  async function publish(ids: string[] | null) {
    const n = ids ? ids.length : waiting.length;
    if (!window.confirm(`Publish ${n} decision${n === 1 ? "" : "s"} for ${session}? Each applicant is told to read the outcome on the portal; a published decision is not changed.`)) return;
    setBusy(true);
    try {
      const out = await cceSend<{ published: Record<string, number> }>("/publish", "POST", { session, applicationIds: ids }, `The CCE admission list of ${session} published (${n})`);
      if (out) { setChosen([]); setTick((t) => t + 1); refresh(); }
    } finally { setBusy(false); }
  }
  function exportList() {
    const blob = buildXlsx(["S/N", "Application number", "JAMB number", "Name", "Programme", "Department", "Faculty", "Study mode", "Admission route", "Session", "Published", "Admission number"],
      admitted.map((r, i) => [i + 1, r.application_no, r.jamb_reg_no, r.name, r.programme, r.department, r.faculty, "PART-TIME", "CCE", session, day(r.published_at), r.admission_no ?? ""]), "CCE admission list");
    downloadBlob(blob, `cce-admission-list-${session.replace("/", "-")}.xlsx`);
  }
  const row = (r: AppRow, pickable: boolean) => [
    pickable ? <input key="c" type="checkbox" aria-label={`Choose ${r.name}`} checked={chosen.includes(r.id)} onChange={() => setChosen((x) => (x.includes(r.id) ? x.filter((y) => y !== r.id) : [...x, r.id]))} /> : <span key="c" />,
    <Link key="a" href={`/cce/applications/${r.id}`} className="tnum">{r.application_no}<div className="sub2">{r.jamb_reg_no}</div></Link>,
    r.name, <span key="p">{r.programme}<div className="sub2">{r.faculty ?? ""}</div></span>,
    <Pil key="s" kind={labelOf(REVIEW_LABEL, r.state)[1]}>{labelOf(REVIEW_LABEL, r.state)[0]}</Pil>,
    <span key="d" className="sub2">{r.decided_at ? `${day(r.decided_at)} · ${r.decided_office ?? ""}` : "—"}</span>,
  ];
  return (
    <>
      <PageHead title="CCE admission list" description={session} actions={pick} />
      <Panel title={`Waiting to be published · ${waiting.length}`} right={powers.academic && waiting.length ? <span className="row row--inline row--tight">
        <Btn kind="secondary" disabled={busy || !chosen.length} onClick={() => void publish(chosen)}>Publish the {chosen.length} chosen</Btn>
        <Btn kind="go" disabled={busy} onClick={() => void publish(null)}>Publish all {waiting.length}</Btn>
      </span> : null}>
        {waiting.length ? <DTable pageSize={0} cols={["", "Application", "Name", "Programme", "Decision", "Decided"]} rows={waiting.map((r) => row(r, powers.academic))} />
          : <PBody><div className="sub2">Nothing waits to be published.</div></PBody>}
        {!powers.academic && waiting.length ? <PBody><div className="sub2">The Academic Office publishes the list.</div></PBody> : null}
      </Panel>
      <Panel title={`Admitted · ${admitted.length}`} right={admitted.length ? <Btn kind="ghost" onClick={exportList}>Export (Excel)</Btn> : null}>
        {admitted.length ? <DTable cols={["", "Application", "Name", "Programme", "Decision", "Decided"]} texts={admitted.map((r) => `${r.name} ${r.application_no} ${r.jamb_reg_no} ${r.programme}`)} rows={admitted.map((r) => row(r, false))} />
          : <PBody><div className="sub2">No admission published yet.</div></PBody>}
      </Panel>
      {declined.length ? <Panel title={`Not admitted · ${declined.length}`}><DTable cols={["", "Application", "Name", "Programme", "Decision", "Decided"]} rows={declined.map((r) => row(r, false))} /></Panel> : null}
    </>
  );
}

/* ── the CCE students ───────────────────────────────────────────────────────────────────────────────────────────── */

export function CceStudents({ session, pick }: TabProps) {
  const [all, setAll] = useState(false);
  const [q, setQ] = useState("");
  const [query, setQuery] = useState("");
  const [page, setPage] = useState(0);
  const [data, setData] = useState<Paged<StudentRow> | null>(null);
  useEffect(() => {
    let live = true;
    void ccall<Paged<StudentRow>>(`/api/v1/cce/students?session=${all ? "" : encodeURIComponent(session)}&q=${encodeURIComponent(query)}&page=${page}&size=50`)
      .then((r) => { if (!live) return; if (r.ok) setData(r.data); else notifyProblem(r.problem); });
    return () => { live = false; };
  }, [session, all, query, page]);
  return (
    <>
      <PageHead title="CCE students"  actions={pick} />
      <Panel title={all ? "Every CCE student" : `Admitted for ${session}`} right={<span className="row row--inline row--tight">
        <form onSubmit={(e) => { e.preventDefault(); setQuery(q.trim()); setPage(0); }}><input className="ctl" style={{ width: 220 }} placeholder="Matric, admission, JAMB number, name" aria-label="Search the CCE students" value={q} onChange={(e) => setQ(e.target.value)} /></form>
        <label className="row row--inline row--tight"><input type="checkbox" checked={all} onChange={(e) => { setAll(e.target.checked); setPage(0); }} /> every session</label>
      </span>}>
        {data === null ? <PBody><div className="sub2">Reading…</div></PBody> : data.rows.length ? (
          <>
            <DTable pageSize={0} cols={["Number", "Name", "Programme", "Level|num", "Entry session", "Expected completion", "Status"]} rows={data.rows.map((s) => [
              <span key="n" className="tnum">{s.matric_no ?? s.admission_no ?? "—"}<div className="sub2">{s.jamb_reg_no}</div></span>,
              s.name, <span key="p">{s.programme}<div className="sub2">{s.department ?? ""}</div></span>, s.current_level,
              <span key="e" className="tnum">{s.entry_session}</span>,
              <span key="x" className="tnum">{s.expected_completion ?? "—"}{s.duration_years ? <div className="sub2">{s.duration_years} years, part-time</div> : null}</span>,
              <Pil key="s" kind={s.status === "ACTIVE" ? "ok" : "grey"}>{s.status.toLowerCase()}</Pil>,
            ])} />
            <Pager total={data.total} page={page} size={data.size} onPage={setPage} />
          </>
        ) : <PBody><div className="sub2">No CCE student on the register{all ? "" : ` for ${session}`} yet.</div></PBody>}
      </Panel>
    </>
  );
}
