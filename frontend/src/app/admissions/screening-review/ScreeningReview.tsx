"use client";

/** The screening officers' desk (V269): the counts, the queue searched and filtered on the server, one form in full — the
 *  answers by section, the institutions, the O'Level results declared beside JAMB's, the documents opened through the
 *  authorised door, the engine's reading, the trail — and the decision: successful, unsuccessful with the reason, or
 *  returned for correction. The policy of the session (on/off, required documents and fields) is edited here. */
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { useQueryNav } from "@/lib/query-nav";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import type { Problem } from "@/lib/api";
import { Btn, KvGrid, LinkBtn, Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { DOC_WORD, SECTION_WORD, STATE_WORD, dayOf, parseTracker, whenAt, type Facts, type ReviewDetail, type ReviewList, type ReviewRow, type ScreeningState } from "@/lib/screening";
import { Tracker } from "@/app/applicant/Admission";
import { ProgrammeChange } from "./ProgrammeChange";

export interface ReviewFilters { session: string; state: string; fac: string; dept: string; prog: string; q: string; from: string; to: string; open: string }
const OFFICE = ["academic", "registrar", "dregistrar", "super"];

export function ScreeningReview({ list, filters, actingOffice }: { list: ReviewList; filters: ReviewFilters; actingOffice: string | null }) {
  const router = useRouter();
  const queryNav = useQueryNav();
  const may = OFFICE.includes(actingOffice ?? "");
  const mayOverride = ["registrar", "dregistrar", "dvc", "vc", "super"].includes(actingOffice ?? "");
  const [changing, setChanging] = useState(false);
  const [q, setQ] = useState(filters.q);
  const [busy, setBusy] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [open, setOpen] = useState<ReviewDetail | null>(null);
  const [deciding, setDeciding] = useState<"SUCCESSFUL" | "UNSUCCESSFUL" | "CORRECTION" | null>(null);
  const [reason, setReason] = useState("");
  const [remarks, setRemarks] = useState("");
  const [policyOpen, setPolicyOpen] = useState(false);
  const [pol, setPol] = useState({ enabled: list.policy?.enabled ?? true, docs: (list.policy?.required_documents ?? []).join(", "), fields: (list.policy?.required_fields ?? []).join(", "), instructions: list.policy?.instructions ?? "" });
  const base = `/api/bff/api/v1/admissions/sessions/${filters.session}`;
  const t = list.stats;
  const rows = list.rows;

  const go = (next: Partial<ReviewFilters>) => { const f = { ...filters, ...next }; if (next.fac !== undefined) { f.dept = ""; f.prog = ""; } const qs = new URLSearchParams(); for (const [k, v] of Object.entries(f)) if (v) qs.set(k, v); queryNav(`/admissions/screening-review?${qs}`); };
  const link = (extra: Partial<ReviewFilters>) => { const f = { ...filters, ...extra }; const qs = new URLSearchParams(); for (const [k, v] of Object.entries(f)) if (v) qs.set(k, v); return `/admissions/screening-review?${qs}`; };
  async function openOne(id: string) {
    setBusy(id);
    try {
      const r = await fetch(`${base}/screening-review/${id}`, { cache: "no-store" });
      const j = await r.json().catch(() => null);
      if (!r.ok) { notifyProblem((j as Problem) ?? { status: r.status, title: r.statusText }); return; }
      setOpen(j as ReviewDetail);
    } finally { setBusy(null); }
  }
  useEffect(() => {
    if (!filters.open) return;
    let live = true;
    fetch(`${base}/screening-review/${filters.open}`, { cache: "no-store" }).then(async (r) => { const j = await r.json().catch(() => null); if (!live) return; if (r.ok) setOpen(j as ReviewDetail); else notifyProblem((j as Problem) ?? { status: r.status, title: r.statusText }); }).catch(() => undefined);
    return () => { live = false; };
  }, [filters.open, base]);
  async function call<T>(path: string, method: "POST" | "PUT", body: unknown, label: string, key: string): Promise<T | null> {
    setBusy(key); setProblem(null);
    try {
      const r = await fetch(`${base}${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(label) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { const pr = (j as Problem) ?? { status: r.status, title: r.statusText }; setProblem(pr); notifyProblem(pr); return null; }
      notify(label); return j as T;
    } finally { setBusy(null); }
  }
  const start = async () => { if (!open) return; const d = await call<ReviewDetail>(`/screening-review/${open.application.id}/start`, "POST", {}, "Review started", "start"); if (d) { setOpen(d); router.refresh(); } };
  const decide = async () => {
    if (!open || !deciding) return;
    if (deciding !== "SUCCESSFUL" && !reason.trim()) { const pr: Problem = { status: 422, title: deciding === "CORRECTION" ? "Say what must be corrected." : "An unsuccessful screening carries its reason." }; setProblem(pr); notifyProblem(pr); return; }
    const d = await call<ReviewDetail>(`/screening-review/${open.application.id}/decide`, "POST", { decision: deciding, reason: reason.trim() || null, remarks: remarks.trim() || null },
      deciding === "SUCCESSFUL" ? `${open.application.surname} successfully screened` : deciding === "UNSUCCESSFUL" ? `${open.application.surname}: screening unsuccessful` : `${open.application.surname}: correction required`, "decide");
    if (d) { setOpen(d); setDeciding(null); setReason(""); setRemarks(""); router.refresh(); }
  };
  const savePolicy = async () => {
    const r = await call<unknown>("/screening-policy", "PUT", { enabled: pol.enabled, requiredDocuments: pol.docs.split(/[,\n]/).map((x) => x.trim().toUpperCase()).filter(Boolean), requiredFields: pol.fields.split(/[,\n]/).map((x) => x.trim()).filter(Boolean), instructions: pol.instructions.trim() || null }, "Screening policy saved", "policy");
    if (r) { setPolicyOpen(false); router.refresh(); }
  };
  const state = (r: ReviewRow) => (r.state ? <Pil kind={STATE_WORD[r.state as ScreeningState][1]}>{STATE_WORD[r.state as ScreeningState][0]}</Pil> : <Pil kind="grey">NOT STARTED</Pil>);
  const faculties = [...new Map(list.options.map((o) => [o.faculty_code, o.faculty])).entries()];
  const depts = [...new Map(list.options.filter((o) => !filters.fac || o.faculty_code === filters.fac).filter((o) => o.dept_code).map((o) => [o.dept_code as string, o.department as string])).entries()];
  const progs = [...new Map(list.options.filter((o) => (!filters.fac || o.faculty_code === filters.fac) && (!filters.dept || o.dept_code === filters.dept)).map((o) => [o.programme_code, o.programme])).entries()];
  const HEAD = ["S/N", "Applicant", "JAMB No.", "Application No.", "Faculty", "Department", "Programme", "Screening No.", "Status", "Submitted", "Decided", "Reason / note", "Change of programme"];
  const body = () => [...rows].sort((a, b) => `${a.surname} ${a.other_names}`.localeCompare(`${b.surname} ${b.other_names}`)).map((r, i) => [i + 1, `${r.surname}, ${r.other_names}`, r.jamb_reg_no, r.application_no, r.faculty ?? "", r.department ?? "", r.programme, r.screening_no ?? "", r.state ? STATE_WORD[r.state as ScreeningState][0] : "NOT STARTED", dayOf(r.submitted_at), dayOf(r.decided_at), r.decision_reason ?? r.returned_note ?? "", r.change_state ? `${r.change_to} · ${r.change_state}` : ""]);
  const sub = [filters.state, filters.fac, filters.dept, filters.prog, filters.q ? `search “${filters.q}”` : ""].filter(Boolean).join(" · ") || "Every accepted applicant";
  const excel = async () => { const blob = await brandedXlsx("Screening Report", HEAD, body(), { sheetName: "Screening", serial: docSerial("SCR"), sub: `${filters.session} · ${sub}` }); downloadBlob(blob, "screening-report.xlsx"); };
  const a = open?.application;
  const f = open?.form ?? null;
  const sections = open ? [...new Set(open.answers.map((x) => x.section))] : [];
  const facts: Facts | null = (() => { try { return open?.facts ? (JSON.parse(open.facts) as Facts) : null; } catch { return null; } })();

  return (
    <>
      <PageHead title="Screening review" description={`${filters.session} · the accepted applicants screened on the record the University already holds — JAMB, the application, the documents — nothing filled by them; decided on the record. A successful screening opens school fees and registration; an unsuccessful one carries its reason, and the eligibility engine lists the programmes the candidate qualifies for; the acceptance fee is never charged again.`}
        actions={<><LinkBtn kind="ghost" href={`/admissions?session=${encodeURIComponent(filters.session)}`}>Admissions</LinkBtn><LinkBtn kind="ghost" href={`/admissions/eligibility?session=${encodeURIComponent(filters.session)}`}>Programme Eligibility</LinkBtn>
          {may ? <Btn kind="ghost" onClick={() => setPolicyOpen(true)}>Screening policy{list.policy ? (list.policy.enabled ? " · ON" : " · OFF") : ""}</Btn> : null}
          <Btn kind="secondary" disabled={!rows.length} onClick={() => void excel()}>Excel</Btn><Btn kind="ghost" disabled={!rows.length} onClick={() => brandedPrint("Screening Report", `${filters.session} · ${sub}`, HEAD, body(), docSerial("SCR"))}>PDF</Btn></>} />
      {problem ? <ProblemNotice problem={problem} /> : null}
      {list.policy && !list.policy.enabled ? <Note kind="info" title="Online screening is off for this session">Applicants proceed to school fees on acceptance; turn it on under Screening policy.</Note> : null}
      <Tiles items={[
        ["Screenings opened", String(t.total), null, "Accepted applicants this session", link({ state: "" })],
        ["Awaiting screening", String(t.pending), t.pending ? "var(--chrome)" : null, "Accepted; the record awaits the office", link({ state: "PENDING" })],
        ["Not yet opened", String(t.submitted), null, "Awaiting, nobody has opened the record", link({ state: "PENDING" })],
        ["In review", String(t.in_review), null, "Opened by an officer", link({ state: "IN_REVIEW" })],
        ["Successful", String(t.successful), "var(--green-ink)", "Cleared to pay school fees", link({ state: "SUCCESSFUL" })],
        ["Unsuccessful", String(t.unsuccessful), t.unsuccessful ? "var(--red-ink)" : null, "With the reason on the record", link({ state: "UNSUCCESSFUL" })],
        ["Correction required", String(t.returned), t.returned ? "var(--amber-ink)" : null, "One thing asked of the applicant", link({ state: "CORRECTION" })],
        ["Change of programme requested", String(t.change_requested), t.change_requested ? "var(--amber-ink)" : null, "Decided on Programme Eligibility", link({ state: "CHANGE" })],
        ["Completed", String(t.completed), "var(--green-ink)", "Successful, or change approved", link({ state: "COMPLETED" })],
        ["Overdue", String(t.overdue), t.overdue ? "var(--red-ink)" : null, "Accepted over 7 days ago, undecided", link({ state: "OVERDUE" })],
      ]} cls="grid--5" />
      <div className="scope">
        <div className="scope__f"><Field id="sr-state" label="Screening status"><select id="sr-state" className="ctl" value={filters.state} onChange={(e) => go({ state: e.target.value })}><option value="">Every status</option><option value="PENDING">Awaiting screening</option><option value="IN_REVIEW">In review</option><option value="SUCCESSFUL">Successful</option><option value="UNSUCCESSFUL">Unsuccessful</option><option value="CORRECTION">Correction required</option><option value="CHANGE">Change of programme requested</option><option value="COMPLETED">Completed</option><option value="OVERDUE">Overdue</option></select></Field></div>
        <div className="scope__f"><Field id="sr-fac" label="Faculty"><select id="sr-fac" className="ctl" value={filters.fac} onChange={(e) => go({ fac: e.target.value })}><option value="">All</option>{faculties.map(([c, n]) => <option key={c} value={c}>{n}</option>)}</select></Field></div>
        <div className="scope__f"><Field id="sr-dept" label="Department"><select id="sr-dept" className="ctl" value={filters.dept} onChange={(e) => go({ dept: e.target.value })}><option value="">All</option>{depts.map(([c, n]) => <option key={c} value={c}>{n}</option>)}</select></Field></div>
        <div className="scope__f"><Field id="sr-prog" label="Programme"><select id="sr-prog" className="ctl" value={filters.prog} onChange={(e) => go({ prog: e.target.value })}><option value="">All</option>{progs.map(([c, n]) => <option key={c} value={c}>{n}</option>)}</select></Field></div>
        <div className="scope__f"><Field id="sr-from" label="Submitted from"><input id="sr-from" type="date" className="ctl" value={filters.from} onChange={(e) => go({ from: e.target.value })} /></Field></div>
        <div className="scope__f"><Field id="sr-to" label="to"><input id="sr-to" type="date" className="ctl" value={filters.to} onChange={(e) => go({ to: e.target.value })} /></Field></div>
        <div className="scope__f grow"><Field id="sr-q" label="Search" hint="Applicant name, JAMB number, application or screening number, programme"><form className="scope__search" onSubmit={(e) => { e.preventDefault(); go({ q: q.trim() }); }}><input id="sr-q" className="ctl" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search…" /><Btn kind="primary" type="submit">Search</Btn><Btn kind="ghost" onClick={() => { setQ(""); queryNav(`/admissions/screening-review?session=${encodeURIComponent(filters.session)}`); }}>Reset</Btn></form></Field></div>
      </div>

      <Panel title="Screening queue" right={`${rows.length} · names A–Z${rows.length >= 500 ? " · first 500; narrow the search" : ""}`}>
        {rows.length ? (
          <DTable pageSize={0} cols={["S/N|num", "Applicant", "Programme", "Screening|mid", "Submitted|mid", "Documents|mid", "Decision / note", "|num"]} rows={rows.map((r, i) => [
            <span key="sn" className="tnum sub2">{i + 1}</span>,
            <span key="a"><strong>{r.surname}, {r.other_names}</strong><div className="sub2 tnum">{r.jamb_reg_no} · {r.application_no}{r.screening_no ? ` · ${r.screening_no}` : ""}{r.admission_no ? ` · ${r.admission_no}` : ""}</div></span>,
            <span key="p">{r.programme}<div className="sub2">{r.faculty ?? ""}{r.department ? ` · ${r.department}` : ""}</div></span>,
            <span key="s">{state(r)}{r.overdue ? <div><Pil kind="bad">Overdue</Pil></div> : null}{r.change_state ? <div className="sub2">{r.change_to} · {r.change_state}</div> : null}</span>,
            <span key="d" className="tnum sub2">{dayOf(r.submitted_at)}{r.version && r.version > 1 ? ` · v${r.version}` : ""}</span>,
            <span key="n" className="tnum">{r.documents}</span>,
            <span key="r" className="sub2">{r.decision_reason ?? r.returned_note ?? r.remarks ?? ""}</span>,
            <span key="x" className="row row--inline row--tight row--end"><Btn kind={r.state === "PENDING" || r.state === "IN_REVIEW" ? "primary" : "ghost"} size="sm" disabled={busy === r.id} onClick={() => void openOne(r.id)}>{r.state === "PENDING" || r.state === "IN_REVIEW" ? "Review" : "Open"}</Btn></span>,
          ])} texts={rows.map((r) => `${r.surname} ${r.other_names} ${r.jamb_reg_no} ${r.application_no} ${r.programme} ${r.screening_no ?? ""}`)} />
        ) : <PBody><Note kind="info" title="No records found">No accepted applicant matches the filters for {filters.session}.</Note></PBody>}
      </Panel>

      {open && a ? (
        <Modal title={`${a.surname}, ${a.other_names} · ${f?.screening_no ?? a.application_no}`} sub={`${a.programme} · ${a.faculty ?? ""}${a.department ? ` · ${a.department}` : ""} · ${a.jamb_reg_no} · ${a.entry_mode.replace("_", " ")}`} wide onClose={() => { setOpen(null); router.push(link({ open: "" })); }}
          foot={<>{f && may && ["PENDING", "IN_REVIEW", "CORRECTION_REQUIRED", "UNSUCCESSFUL"].includes(f.state) ? <Btn kind="secondary" disabled={busy !== null} onClick={() => setChanging(true)}>Change course / programme</Btn> : null}{f && may && ["PENDING", "IN_REVIEW", "CORRECTION_REQUIRED"].includes(f.state) ? <><Btn kind="go" disabled={busy !== null} onClick={() => { setDeciding("SUCCESSFUL"); setReason(""); setRemarks(""); }}>Approve screening</Btn><Btn kind="urgent" disabled={busy !== null} onClick={() => { setDeciding("UNSUCCESSFUL"); setReason(""); setRemarks(""); }}>Unsuccessful</Btn><Btn kind="secondary" disabled={busy !== null} onClick={() => { setDeciding("CORRECTION"); setReason(""); setRemarks(""); }}>Request correction</Btn>{f.state === "SUBMITTED" ? <Btn kind="ghost" disabled={busy !== null} onClick={() => void start()}>Mark in review</Btn> : null}</> : null}<span className="grow" /><Btn kind="primary" onClick={() => { setOpen(null); router.push(link({ open: "" })); }}>Close</Btn></>}>
          <div className="stack">
            <div className="row row--between"><span className="row row--inline row--tight">{f ? <Pil kind={STATE_WORD[f.state][1]}>{STATE_WORD[f.state][0]}</Pil> : <Pil kind="grey">NOT STARTED</Pil>}<span className="sub2">{open.status.label}{open.status.next_action ? ` · next: ${open.status.next_action}` : ""}</span></span><span className="sub2">Acceptance fee {open.entitlement.paid ? <Pil kind="ok">PAID</Pil> : <Pil kind="warn">UNPAID</Pil>}</span></div>
            <Tracker steps={parseTracker(open.tracker)} compact />
            {f?.state === "UNSUCCESSFUL" ? <Note kind="bad" title="Unsuccessful">{f.decision_reason}{f.remarks ? ` · ${f.remarks}` : ""}{open.eligibility ? <span className="blk">Engine: {open.eligibility.alternatives} eligible alternative(s){open.eligibility.eligible_alternatives ? ` — ${open.eligibility.eligible_alternatives}` : ""}</span> : null}</Note> : null}
            {f?.state === "CORRECTION_REQUIRED" ? <Note kind="info" title="Correction required of the applicant">{f.returned_note}</Note> : null}
            {open.missing.length ? <div className="sub2">Not on the record (the University does not hold it; the form leaves it blank): {open.missing.map((m) => m.label).join(" · ")}</div> : null}
            {facts ? <FactsBlock facts={facts} /> : null}
            <div className="eyebrow">On record</div>
            <KvGrid cls="grid--4" pairs={[["Sex", open.prefill.sex ?? "—"], ["Date of birth", open.prefill.date_of_birth ?? "—"], ["State / LGA (JAMB)", `${open.prefill.state_of_origin ?? "—"} / ${open.prefill.lga ?? "—"}`], ["UTME", open.utme ? `${open.utme.aggregate ?? "—"} · ${open.utme.subjects ?? ""}` : "—"], ["Email", open.prefill.email], ["Phone", open.prefill.phone], ["Next of kin (application)", open.prefill.next_of_kin ?? "—"], ["Admission no.", a.admission_no ?? "Not yet on the register"]]} />
            {sections.map((sec) => <div key={sec}><div className="eyebrow mb-1">{SECTION_WORD[sec] ?? sec}</div><KvGrid cls="grid--3" pairs={open.answers.filter((x) => x.section === sec).map((x) => [x.label, x.value] as [string, string])} /></div>)}
            {f?.membership ? <KvGrid cls="grid--1" pairs={[["Membership of associations", f.membership]]} /> : null}
            <div className="eyebrow">Institutions attended</div>
            {open.institutions.length ? <DTable pageSize={0} cols={["S/N|num", "Institution", "From|mid", "To|mid", "Certificate", "Year|mid"]} rows={open.institutions.map((it, i) => [<span key="sn" className="tnum sub2">{i + 1}</span>, it.name, <span key="f" className="tnum">{it.from_year ?? ""}</span>, <span key="t" className="tnum">{it.to_year ?? ""}</span>, it.certificate ?? "", <span key="y" className="tnum">{it.award_year ?? ""}</span>])} /> : <div className="sub2">None declared.</div>}
            <div className="grid grid--2">
              <div><div className="eyebrow mb-1">O&rsquo;Level as declared</div>{open.olevel.length ? <DTable pageSize={0} cols={["Body", "Subject", "Exam no.", "Grade|mid", "Year|mid"]} rows={open.olevel.map((r, i) => [<span key={i} className="sub2">{r.exam_body}</span>, r.subject, <span key="n" className="tnum sub2">{r.exam_number ?? ""}</span>, <b key="g" className="tnum">{r.grade}</b>, <span key="y" className="tnum">{r.exam_year ?? ""}</span>])} /> : <div className="sub2">None.</div>}</div>
              <div><div className="eyebrow mb-1">O&rsquo;Level as JAMB sent it</div>{open.jambOlevel.length ? <DTable pageSize={0} cols={["Body", "Subject", "Exam no.", "Grade|mid", "Year|mid"]} rows={open.jambOlevel.map((r, i) => [<span key={i} className="sub2">{r.exam_body}</span>, r.subject, <span key="n" className="tnum sub2">{r.exam_number ?? ""}</span>, <b key="g" className="tnum">{r.grade}</b>, <span key="y" className="tnum">{r.exam_year ?? ""}</span>])} /> : <div className="sub2">None on record.</div>}</div>
            </div>
            <div className="eyebrow">Documents</div>
            {open.documents.length ? <DTable pageSize={0} cols={["Document", "File", "Status|mid", "|num"]} rows={open.documents.map((d) => [<b key="k">{DOC_WORD[d.kind] ?? d.kind}</b>, <span key="f" className="sub2">{d.filename} · {Math.round(d.bytes / 1024)} KB · {whenAt(d.uploaded_at)}{d.review_note ? ` · ${d.review_note}` : ""}</span>, <Pil key="s" kind={d.status === "ACCEPTED" ? "ok" : d.status === "REJECTED" ? "bad" : "info"}>{d.status}</Pil>, <a key="o" className="btn btn--ghost btn--sm" href={`${base}/applications/${a.id}/documents/${d.id}/content`} target="_blank" rel="noopener">Open</a>])} /> : <div className="sub2">No document uploaded.</div>}
            {open.changes.length ? <div><div className="eyebrow mb-1">Change of programme</div>{open.changes.map((c) => <div key={c.id} className="sub2">{whenAt(c.requested_at)} · {c.from_programme} → <b>{c.to_programme}</b> · <Pil kind={c.state === "APPROVED" ? "ok" : c.state === "REQUESTED" ? "warn" : "grey"}>{c.state}</Pil>{c.decision_note ? ` · ${c.decision_note}` : ""}</div>)}<div className="sub2 mt-1"><Link className="lnk" href={`/admissions/eligibility?session=${encodeURIComponent(filters.session)}&status=PENDING_CHANGE`}>Decide on Programme Eligibility</Link></div></div> : null}
            {open.events.length ? <div><div className="eyebrow mb-1">Trail</div>{open.events.slice(0, 15).map((e, i) => <div key={i} className="sub2"><span className="tnum">{whenAt(e.at)}</span> · <b>{e.action.replace(/_/g, " ").toLowerCase()}</b>{e.detail ? ` · ${e.detail}` : ""}{e.officer ? ` · ${e.officer}` : ""}{e.actor_office ? ` (${e.actor_office})` : ""}</div>)}</div> : null}
          </div>
        </Modal>
      ) : null}
      {changing && open && a ? (
        <Modal title={`Change course / programme · ${a.surname}, ${a.other_names}`} sub="The engine's verdict on the current programme, the alternatives it finds the candidate eligible for under the session's settings, the recommendation and the approval" wide onClose={() => setChanging(false)}
          foot={<Btn kind="ghost" onClick={() => setChanging(false)}>Close</Btn>}>
          <ProgrammeChange base={base} appId={a.id} may={may} mayOverride={mayOverride}
            current={{ name: `${a.surname}, ${a.other_names}`, programme: a.programme, faculty: a.faculty ?? null, department: a.department ?? null, session: filters.session, jamb: a.jamb_reg_no, utme: open.utme?.aggregate ?? null, screeningState: f?.state ?? null }}
            onChanged={() => { void openOne(a.id); router.refresh(); }} />
        </Modal>
      ) : null}
      {deciding && open ? (
        <Modal title={deciding === "SUCCESSFUL" ? "Approve the screening" : deciding === "UNSUCCESSFUL" ? "Screening unsuccessful" : "Ask for one correction"} sub={`${open.application.surname}, ${open.application.other_names} · ${open.application.programme}`} onClose={() => setDeciding(null)}
          foot={<><Btn kind="ghost" onClick={() => setDeciding(null)}>Back</Btn><Btn kind={deciding === "SUCCESSFUL" ? "go" : deciding === "UNSUCCESSFUL" ? "urgent" : "primary"} disabled={busy !== null} onClick={() => void decide()}>{deciding === "SUCCESSFUL" ? "Record: successfully screened" : deciding === "UNSUCCESSFUL" ? "Record: unsuccessful" : "Return to the applicant"}</Btn></>}>
          <p className="sub2">{deciding === "SUCCESSFUL" ? "The applicant is told they may pay school fees and commence registration; the answers go onto the student record; the form is closed." : deciding === "UNSUCCESSFUL" ? "The applicant is told the reason; the eligibility engine lists the programmes they qualify for and they may request a change of programme — the acceptance fee is not charged again." : "The form goes back to the applicant with your note; they correct it and submit again."}</p>
          {deciding !== "SUCCESSFUL" ? <Field id="dc-reason" label={deciding === "UNSUCCESSFUL" ? "Reason (required, shown to the applicant)" : "What must be corrected (required)"} required><textarea id="dc-reason" className="ctl" rows={3} value={reason} onChange={(e) => setReason(e.target.value)} /></Field> : null}
          <Field id="dc-remarks" label="Officer's remarks" hint="Optional · on the record"><textarea id="dc-remarks" className="ctl" rows={2} value={remarks} onChange={(e) => setRemarks(e.target.value)} /></Field>
        </Modal>
      ) : null}
      {policyOpen ? (
        <Modal title={`Screening policy · ${filters.session}`} sub="On or off, from when, the documents and the fields required" onClose={() => setPolicyOpen(false)}
          foot={<><Btn kind="ghost" onClick={() => setPolicyOpen(false)}>Back</Btn><Btn kind="primary" disabled={busy !== null} onClick={() => void savePolicy()}>Save the policy</Btn></>}>
          <label className="row row--tight mb-2" style={{ gap: 8 }}><input type="checkbox" className="pchk" checked={pol.enabled} onChange={(e) => setPol({ ...pol, enabled: e.target.checked })} /> Online screening required before school fees and registration{list.policy ? <span className="sub2"> · from {whenAt(list.policy.enabled_from)}; those who accepted earlier are not held</span> : null}</label>
          <Field id="pol-docs" label="Required documents" hint={`Comma-separated kinds: ${Object.keys(DOC_WORD).join(", ")}`}><textarea id="pol-docs" className="ctl" rows={2} value={pol.docs} onChange={(e) => setPol({ ...pol, docs: e.target.value })} /></Field>
          <Field id="pol-fields" label="Required fields" hint="Comma-separated field keys of the biodata catalogue (e.g. nationality, state_of_origin, lga, home_address, mobile, sponsor_name, kin_name)"><textarea id="pol-fields" className="ctl" rows={3} value={pol.fields} onChange={(e) => setPol({ ...pol, fields: e.target.value })} /></Field>
          <Field id="pol-inst" label="Instructions shown on the form" hint="Optional"><textarea id="pol-inst" className="ctl" rows={2} value={pol.instructions} onChange={(e) => setPol({ ...pol, instructions: e.target.value })} /></Field>
        </Modal>
      ) : null}
    </>
  );
}


/** the record the officers screen (V280): identity, JAMB, admission, O'Level, documents and payments as the University holds them */
function FactsBlock({ facts }: { facts: Facts }) {
  const v = (x: unknown) => (x == null || x === "" ? "—" : typeof x === "boolean" ? (x ? "Yes" : "No") : String(x));
  const id = facts.identity ?? {}, jb = facts.jamb ?? {}, ad = facts.admission ?? {}, pay = facts.payments ?? {};
  return (
    <div className="stack">
      <div className="eyebrow">Identity (JAMB and the application)</div>
      <KvGrid cls="grid--4" pairs={[["Sex", id.sex === "M" ? "Male" : id.sex === "F" ? "Female" : v(id.sex)], ["Date of birth", v(id.date_of_birth)], ["State of origin", v(id.state_of_origin)], ["Local government", v(id.lga)], ["Email", v(id.email)], ["Phone", v(id.phone)], ["Next of kin", v(id.next_of_kin)], ["Photograph", id.passport ? "As JAMB sent it" : "Not received"]]} />
      <div className="eyebrow">JAMB information</div>
      <KvGrid cls="grid--4" pairs={[["Registration number", v(jb.jamb_reg_no)], ["UTME aggregate", v(jb.utme_aggregate)], ["UTME subjects", v(jb.utme_subjects)], ["Entry mode / level", `${v(jb.entry_mode)} · ${v(jb.entry_level)}`], ["Programme on the list", v(jb.programme)], ["List source", v(jb.list_source)]]} />
      <div className="eyebrow">Admission information</div>
      <KvGrid cls="grid--4" pairs={[["Programme", v(ad.programme)], ["Faculty", v(ad.faculty)], ["Department", v(ad.department)], ["Decision / basis", `${v(ad.decision)} · ${v(ad.decision_basis)}`], ["Released", ad.decision_released_at ? whenAt(String(ad.decision_released_at)) : "—"], ["Accepted", ad.accepted_at ? whenAt(String(ad.accepted_at)) : "—"], ["Admission number", v(ad.admission_no)], ["Matriculation number", v(ad.matric_no)]]} />
      <div className="eyebrow">Payment status</div>
      <KvGrid cls="grid--3" pairs={(["APPLICATION", "CHECKING", "ACCEPTANCE"] as const).map((k) => { const x = pay[k]; return [k === "APPLICATION" ? "Application fee" : k === "CHECKING" ? "Admission checking fee" : "Acceptance fee", x ? `${x.reference ?? ""} · ${x.confirmed_at ? dayOf(String(x.confirmed_at)) : ""}` : "Not paid"] as [string, string]; })} />
    </div>
  );
}
