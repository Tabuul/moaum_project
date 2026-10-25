"use client";
/** V658: one partnership proposal — where it stands, what the acting office may do next (the server's own list), the answers,
 *  the reviews and notes, the messages with the applicant, due diligence, documents, agreements, the partnership under way,
 *  and the timeline. Every change is the server's: the page reads the record again after each one. */
import { useCallback, useEffect, useState, type ReactNode } from "react";
import Link from "next/link";
import { Btn, Note, Panel, PBody, Pil, Spinner, Tabs } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Problem } from "@/lib/api";
import {
  ACTION_NEEDS, ACTION_WORDS, AGREEMENT_STATUS, AGREEMENT_TYPES, COI, CONTACT_METHODS, FLAG_WORDS, FORMATS, FUNDING, HIGH_RISK, INTERNATIONAL_ASPECTS, JOINT_GRANT, ORG_TYPES,
  OWN_DD, PROPOSAL_KINDS, RESOURCES, SENSITIVE_KINDS, STATUS_WORDS, YES_NO_NOT_SURE, CURRENCIES, countries, dateWords, eventWord, money, statusWord, word, words,
} from "@/lib/partnerships";
import { can, ptnCall, type DeskData } from "../ptn-call";
import { Agreements, Documents, DueDiligence, Messages, Progress, Review, type Detail, type Row } from "./ProposalParts";

type TabId = "proposal" | "review" | "messages" | "diligence" | "documents" | "agreements" | "progress" | "timeline";
const TERMINAL = ["DECLINED", "CLOSED", "CANCELLED"];
const s = (v: unknown) => (v == null || v === "" ? "—" : String(v));

export function ProposalView({ id, desk }: { id: string; desk: DeskData }) {
  const [d, setD] = useState<Detail | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [tab, setTab] = useState<TabId>("proposal");
  const [acting, setActing] = useState<string | null>(null);
  const [editing, setEditing] = useState(false);
  const [done, setDone] = useState<string | null>(null);

  const apply = useCallback((r: Awaited<ReturnType<typeof ptnCall<Detail>>>) => { if (r.ok) { setD(r.data); setProblem(null); } else setProblem(r.problem); }, []);
  const load = useCallback(async () => apply(await ptnCall<Detail>(`/${encodeURIComponent(id)}`)), [id, apply]);
  useEffect(() => {
    let alive = true;
    void ptnCall<Detail>(`/${encodeURIComponent(id)}`).then((r) => { if (alive) apply(r); });
    return () => { alive = false; };
  }, [id, apply]);

  if (problem && !d) return <ProblemNotice problem={problem} />;
  if (!d) return <div className="row row--tight sub2"><Spinner /> Reading the proposal…</div>;

  const p = d.proposal;
  const status = String(p.status);
  const terminal = TERMINAL.includes(status);
  const [label, colour] = STATUS_WORDS[status] ?? [status, "grey"];
  const flags = (p.flags as string[] | null) ?? [];
  const after = async (msg: string) => { setDone(msg); await load(); };
  const counts = {
    review: d.reviewers.filter((r) => !r.withdrawn_at).length, messages: d.messages.filter((m) => m.kind !== "INTERNAL_NOTE").length + d.requests.length,
    diligence: d.dueDiligence.length, documents: d.attachments.length, agreements: d.agreements.length, progress: d.activities.length + d.outcomes.length,
  };

  return (
    <div className="stack">
      <div className="row" style={{ gap: 8, flexWrap: "wrap" }}><Link href="/partnerships?tab=proposals" className="sub2">← All proposals</Link></div>
      <Panel title={<span><span className="tnum">{s(p.reference)}</span> · {s(p.title)}</span>} right={<Pil kind={colour}>{label}</Pil>}>
        <PBody>
          <div className="ptn-meta">
            <div><span>Organisation</span><span>{s(p.org_name)}</span></div>
            <div><span>Organisation type</span><span>{p.org_type === "OTHER" ? s(p.org_type_other) : word(ORG_TYPES, p.org_type as string)}</span></div>
            <div><span>Country</span><span>{s(p.country)}</span></div>
            <div><span>Category</span><span>{p.group_label ? `${p.group_label}: ` : ""}{s(p.category_label)}</span></div>
            <div><span>Received</span><span>{dateWords(p.received_at as string, true)}{p.source === "INTERNAL" ? " (recorded by the office)" : ""}</span></div>
            <div><span>Due</span><span style={p.overdue ? { color: "var(--red-ink)", fontWeight: 600 } : undefined}>{p.due_on ? dateWords(p.due_on as string) : "—"}{p.overdue ? " (overdue)" : ""}</span></div>
            <div><span>Owner</span><span>{p.owner_name ? s(p.owner_name) : "Unassigned"}</span></div>
            <div><span>Desk</span><span>{s(p.desk)}{p.routing_note ? <span className="sub2"> — {String(p.routing_note)}</span> : null}</span></div>
            <div><span>Faculty / department</span><span>{s(p.faculty)}{p.department ? ` / ${p.department}` : ""}</span></div>
            <div><span>Risk level (for review)</span><span>{p.risk_level ? String(p.risk_level).charAt(0) + String(p.risk_level).slice(1).toLowerCase() : "—"}</span></div>
            <div><span>Next action</span><span>{s(p.next_action)}</span></div>
            {terminal ? <div><span>Closed</span><span>{dateWords(p.closed_at as string)}{p.close_reason ? ` — ${p.close_reason}` : ""}</span></div> : null}
          </div>
          {flags.length || p.compliance_review ? (
            <div className="mt-1">
              {p.compliance_review ? <Note kind="info" title="Compliance review required">The answers raise matters for the University&apos;s review. The flags below are prompts for reviewers, not legal conclusions.</Note> : null}
              <div className="ptn-flags mt-1" aria-label="Flags for review">{flags.map((f) => <Pil key={f} kind="warn">{FLAG_WORDS[f] ?? f}</Pil>)}</div>
            </div>
          ) : null}
          {d.actions.length || (can(d, "EDIT_PARTNERSHIP") && !terminal) ? (
            <div className="row mt-1" style={{ gap: 8, flexWrap: "wrap" }}>
              {d.actions.map((a) => (
                <Btn key={a} kind={a === "APPROVE" || a === "ACCEPT" || a === "ACTIVATE" ? "go" : a === "DECLINE" ? "urgent" : "secondary"} onClick={() => { setDone(null); setActing(a); }}>
                  {ACTION_WORDS[a] ?? a}
                </Btn>
              ))}
              {can(d, "EDIT_PARTNERSHIP") && !terminal ? <Btn kind="ghost" onClick={() => setEditing(true)}>Correct the record</Btn> : null}
            </div>
          ) : null}
        </PBody>
      </Panel>
      {done ? <Note kind="ok" title={done} /> : null}
      {problem ? <ProblemNotice problem={problem} /> : null}

      <Tabs<TabId> label="Proposal sections" value={tab} onChange={setTab} look="line" items={[
        { id: "proposal", label: "Proposal" }, { id: "review", label: "Reviews & notes", count: counts.review || null },
        { id: "messages", label: "Applicant", count: counts.messages || null }, { id: "diligence", label: "Due diligence", count: counts.diligence || null },
        { id: "documents", label: "Documents", count: counts.documents || null }, { id: "agreements", label: "Agreements", count: counts.agreements || null },
        { id: "progress", label: "Activities & outcomes", count: counts.progress || null }, { id: "timeline", label: "Timeline", count: d.events.length },
      ]} />

      {tab === "proposal" ? <Answers p={p} conf={d.mayConfidential} /> : null}
      {tab === "review" ? <Review d={d} desk={desk} terminal={terminal} after={after} /> : null}
      {tab === "messages" ? <Messages d={d} terminal={terminal} after={after} /> : null}
      {tab === "diligence" ? <DueDiligence d={d} terminal={terminal} after={after} /> : null}
      {tab === "documents" ? <Documents d={d} desk={desk} after={after} /> : null}
      {tab === "agreements" ? <Agreements d={d} desk={desk} after={after} /> : null}
      {tab === "progress" ? <Progress d={d} desk={desk} after={after} /> : null}
      {tab === "timeline" ? <Timeline events={d.events} /> : null}

      {acting ? <ActModal action={acting} d={d} desk={desk} onClose={() => setActing(null)} onDone={async (msg) => { setActing(null); await after(msg); }} /> : null}
      {editing ? <EditModal d={d} desk={desk} onClose={() => setEditing(false)} onDone={async () => { setEditing(false); await after("The record is corrected"); }} /> : null}
    </div>
  );
}

/* ── the answers, as the applicant gave them ── */

function Section({ title, rows }: { title: string; rows: [string, ReactNode][] }) {
  return (
    <section className="ptn-review" aria-label={title}>
      <div className="ptn-reviewhead"><h3>{title}</h3></div>
      <dl className="ptn-dl">{rows.map(([k, v]) => <div key={k} className="ptn-dlrow"><dt>{k}</dt><dd>{v}</dd></div>)}</dl>
    </section>
  );
}

function Answers({ p, conf }: { p: Row; conf: boolean }) {
  const arr = (k: string) => ((p[k] as string[] | null) ?? []);
  let risk: Record<string, string> = {};
  try { risk = p.high_risk_text ? JSON.parse(String(p.high_risk_text)) : {}; } catch { risk = {}; }
  const yn = (v: unknown) => (v === true ? "Yes" : v === false ? "No" : "—");
  return (
    <div className="stack">
      <Section title="Applicant details" rows={[["Name", `${s(p.first_name)} ${p.last_name ?? ""}`.trim()], ["Job title / role", s(p.job_title)], ["Organisation", s(p.org_name)],
        ["Organisation type", p.org_type === "OTHER" ? s(p.org_type_other) : word(ORG_TYPES, p.org_type as string)], ["Work email", p.email ? <a href={`mailto:${p.email}`}>{String(p.email)}</a> : "—"],
        ["Telephone", s(p.phone)], ["Country/territory", s(p.country)], ["City", s(p.city)], ["Address", s(p.address)],
        ["Website", p.website ? <a href={String(p.website)} target="_blank" rel="noopener noreferrer nofollow">{String(p.website)}</a> : "—"],
        ["Profile", p.profile_url ? <a href={String(p.profile_url)} target="_blank" rel="noopener noreferrer nofollow">{String(p.profile_url)}</a> : "—"],
        ["Preferred language", s(p.language)], ["Preferred contact", word(CONTACT_METHODS, p.contact_method as string)], ["Time zone", s(p.time_zone)]]} />
      <Section title="Existing University connection" rows={[["Is this", word(PROPOSAL_KINDS, p.proposal_kind as string)], ["Previous reference", s(p.previous_reference)],
        ["University contact", p.has_contact ? `${s(p.contact_name)}${p.contact_unit ? `, ${p.contact_unit}` : ""}${p.contact_email ? ` (${p.contact_email})` : ""}` : yn(p.has_contact)],
        ["Collaborated before", word(YES_NO_NOT_SURE, p.collaborated_before as string)], ["Previous collaboration", s(p.previous_collaboration)]]} />
      <Section title="Partnership proposal" rows={[["Category", `${p.group_label ? `${p.group_label}: ` : ""}${s(p.category_label)}`], ["Secondary category", s(p.secondary_label)],
        ["Title", s(p.title)], ["Summary", s(p.summary)], ["Description", s(p.description)], ["Objectives", s(p.objectives)], ["Activities", s(p.activities)],
        ["Expected results", s(p.expected_results)], ["Why this University", s(p.why_university)], ["Faculty", s(p.faculty)], ["Department", s(p.department)],
        ["Unit, centre or office", s(p.unit_text)], ["Expertise sought", s(p.expertise)], ["Staff contact", s(p.staff_contact)],
        ["Proposed start", p.start_date ? dateWords(p.start_date as string) : "—"], ["Duration", s(p.duration)], ["Format", word(FORMATS, p.collaboration_format as string)],
        ["Benefits to the University", s(p.benefits_university)], ["Benefits to the partner", s(p.benefits_partner)]]} />
      <Section title="Funding & resources" rows={[["Funding", word(FUNDING, p.funding_status as string)], ["Estimated budget", p.budget != null ? money(p.budget, p.currency as string) : "—"],
        ["Funder", s(p.funder)], ["Joint grant application", word(JOINT_GRANT, p.joint_grant as string)],
        ["Funding deadline", p.funding_deadline ? dateWords(p.funding_deadline as string) : "—"], ["Resources requested", words(RESOURCES, arr("resources_requested"))],
        ["Other resources", s(p.resources_other)], ["Partner's contribution", s(p.partner_contribution)]]} />
      <Section title="International, legal & compliance (flags for review)" rows={[["Partners outside the country", yn(p.international)],
        ["Countries", arr("countries").join(", ") || "—"], ["International aspects", words(INTERNATIONAL_ASPECTS, arr("international_aspects"))],
        ["Formal agreement", words(AGREEMENT_TYPES, arr("agreement_types"))], ["Personal data", word(YES_NO_NOT_SURE, p.personal_data as string)],
        ["Sensitive data", word(YES_NO_NOT_SURE, p.sensitive_data as string)], ["Kinds of sensitive data", words(SENSITIVE_KINDS, arr("sensitive_kinds"))],
        ["Ethics approval", word(YES_NO_NOT_SURE, p.ethics as string)],
        ["High-risk activities", HIGH_RISK.filter(([k]) => risk[k] && risk[k] !== "NO").map(([k, l]) => `${l} (${word(YES_NO_NOT_SURE, risk[k])})`).join(", ") || "None"],
        ["Conflicts of interest", word(COI, p.coi as string)],
        ["Conflict details", conf ? s(p.coi_detail) : p.coi_detail ? <span className="sub2">{String(p.coi_detail)}</span> : "—"],
        ["Own due diligence", word(OWN_DD, p.own_due_diligence as string)]]} />
      <Section title="Declarations" rows={[["Declarations", p.source === "INTERNAL" ? "Recorded by the office (no applicant declarations)" : "All five given at submission"],
        ["Partnership communications", p.consent_marketing ? "Yes" : "No"]]} />
    </div>
  );
}

/* ── the timeline ── */

/** a proposal's status in words, else an agreement's (an agreement's steps are on the same timeline) */
const stepWord = (x: string) => (STATUS_WORDS[x] ? statusWord(x) : AGREEMENT_STATUS[x] ?? x);

function Timeline({ events }: { events: Row[] }) {
  return (
    <Panel title="Timeline">
      <PBody>
        {events.length ? (
          <ol className="ptn-timeline">
            {[...events].reverse().map((e, i) => (
              <li key={i}>
                <div className="row" style={{ gap: 8, flexWrap: "wrap", alignItems: "baseline" }}>
                  <strong>{eventWord(String(e.action))}</strong>
                  {e.to_status && e.to_status !== e.from_status ? <span className="sub2">{e.from_status ? `${stepWord(e.from_status as string)} → ` : ""}{stepWord(e.to_status as string)}</span> : null}
                  {e.applicant_visible ? <Pil kind="info">Shown to the applicant</Pil> : null}
                </div>
                {e.detail ? <div className="ptn-text">{String(e.detail)}</div> : null}
                <div className="sub2">{dateWords(e.at as string, true)} · {e.actor_name ? String(e.actor_name) : e.actor_office ? String(e.actor_office) : "The portal"}</div>
              </li>
            ))}
          </ol>
        ) : <p className="sub2">Nothing yet.</p>}
      </PBody>
    </Panel>
  );
}

/* ── a workflow action: what it asks for, then the server's move ── */

function ActModal({ action, d, desk, onClose, onDone }: { action: string; d: Detail; desk: DeskData; onClose: () => void; onDone: (msg: string) => Promise<void> }) {
  const p = d.proposal;
  const [note, setNote] = useState("");
  const [person, setPerson] = useState(String(p.owner_person ?? ""));
  const [deskCode, setDeskCode] = useState(String(p.desk_code ?? ""));
  const [question, setQuestion] = useState("");
  const [documents, setDocuments] = useState("");
  const [deadline, setDeadline] = useState("");
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const needs = ACTION_NEEDS[action] ?? "note";
  const min = action === "ROUTE" ? 5 : 10;
  const ready = action === "ASSIGN" ? !!person
    : action === "ROUTE" ? !!deskCode && note.trim().length >= min
    : action === "REQUEST_INFORMATION" ? question.trim().length >= 10
    : needs === "reason" ? note.trim().length >= min : true;

  async function go() {
    setBusy(true); setProblem(null);
    const data: Record<string, unknown> = { note: note.trim() || undefined };
    if (action === "ASSIGN") data.person = person;
    if (action === "ROUTE") data.desk = deskCode;
    if (action === "REQUEST_INFORMATION") Object.assign(data, { question: question.trim(), documents: documents.trim() || undefined, deadline: deadline || undefined });
    if (action === "DECLINE") data.message = message.trim() || undefined;
    try {
      const r = await ptnCall<{ status: string }>(`/${p.id}/act`, { method: "POST", body: { action, data }, reason: `${ACTION_WORDS[action] ?? action}: ${p.reference}` });
      if (!r.ok) { setProblem(r.problem); return; }
      await onDone(`${ACTION_WORDS[action] ?? action}: now ${statusWord(r.data.status).toLowerCase()}`);
    } finally { setBusy(false); }
  }

  return (
    <Modal title={ACTION_WORDS[action] ?? action} sub={`${p.reference} · ${p.title}`} onClose={onClose}
      foot={<><Btn kind="ghost" onClick={onClose}>Cancel</Btn><span className="grow" />
        <Btn kind={action === "DECLINE" ? "urgent" : "primary"} busy={busy} busyLabel="Saving…" disabled={!ready} onClick={() => void go()}>{ACTION_WORDS[action] ?? action}</Btn></>}>
      <div className="stack">
        {action === "ASSIGN" ? (
          <Field id="act-person" label="Owner" required hint="An officer of the Linkages & Partnerships office or of one of its desks">
            <select id="act-person" className="ctl" value={person} onChange={(e) => setPerson(e.target.value)}>
              <option value="">Choose…</option>{desk.owners.map((o) => <option key={o.id} value={o.id}>{o.name}</option>)}
            </select>
          </Field>
        ) : null}
        {action === "ROUTE" ? (
          <Field id="act-desk" label="Desk" required>
            <select id="act-desk" className="ctl" value={deskCode} onChange={(e) => setDeskCode(e.target.value)}>
              <option value="">Choose…</option>{desk.desks.filter((k) => k.active).map((k) => <option key={k.code} value={k.code}>{k.label}{k.lead_name ? ` (lead: ${k.lead_name})` : ""}</option>)}
            </select>
          </Field>
        ) : null}
        {action === "REQUEST_INFORMATION" ? (
          <>
            <Note kind="info" title="The applicant is e-mailed the question and answers on their secure status page." />
            <Field id="act-q" label="Question or request" required hint="10 characters at least; this is what the applicant reads">
              <textarea id="act-q" className="ctl" rows={4} maxLength={4000} value={question} onChange={(e) => setQuestion(e.target.value)} />
            </Field>
            <Field id="act-docs" label="Documents asked for" hint="Optional: the applicant uploads them on the status page">
              <input id="act-docs" className="ctl" maxLength={1000} value={documents} onChange={(e) => setDocuments(e.target.value)} />
            </Field>
            <Field id="act-deadline" label="Deadline" hint={`Optional: ${String(desk.settings.info_days ?? 10)} working days from today when left empty`}>
              <input id="act-deadline" type="date" className="ctl" value={deadline} onChange={(e) => setDeadline(e.target.value)} />
            </Field>
          </>
        ) : null}
        {action === "DECLINE" ? (
          <Field id="act-msg" label="Message to the applicant" hint="Optional: courteous and brief; the internal reason below is not sent">
            <textarea id="act-msg" className="ctl" rows={3} maxLength={2000} value={message} onChange={(e) => setMessage(e.target.value)} />
          </Field>
        ) : null}
        {needs !== "none" || action === "ASSIGN" || action === "REQUEST_INFORMATION" ? (
          <Field id="act-note" label={needs === "reason" ? "Reason" : action === "REQUEST_INFORMATION" ? "Internal reason" : "Note"} required={needs === "reason"}
            hint={needs === "reason" ? `${min} characters at least; kept on the timeline` : "Optional; kept on the timeline"}>
            <textarea id="act-note" className="ctl" rows={3} maxLength={2000} value={note} onChange={(e) => setNote(e.target.value)} />
          </Field>
        ) : <p className="sub2">This moves the proposal on and is kept on the timeline.</p>}
        {action === "APPROVE" ? <Note kind="info" title="The applicant is told the proposal is approved for development. An agreement, where one is needed, follows its own review and approval." /> : null}
        {problem ? <ProblemNotice problem={problem} /> : null}
      </div>
    </Modal>
  );
}

/* ── a correction of the record: only what changed is sent, with the reason ── */

const EDITABLE: [string, string, string, "text" | "area" | "email"][] = [
  ["orgName", "org_name", "Organisation name", "text"], ["firstName", "first_name", "Contact first name", "text"], ["lastName", "last_name", "Contact last name", "text"],
  ["jobTitle", "job_title", "Job title / role", "text"], ["email", "email", "Work email", "email"], ["phone", "phone", "Telephone", "text"], ["city", "city", "City", "text"],
  ["website", "website", "Website", "text"], ["title", "title", "Title", "text"], ["summary", "summary", "Summary", "area"], ["description", "description", "Description", "area"],
  ["objectives", "objectives", "Objectives", "area"], ["duration", "duration", "Duration", "text"], ["funder", "funder", "Funder", "text"],
];

function EditModal({ d, desk, onClose, onDone }: { d: Detail; desk: DeskData; onClose: () => void; onDone: () => Promise<void> }) {
  const p = d.proposal;
  const initial: Record<string, string> = {};
  for (const [k, col] of EDITABLE) initial[k] = p[col] == null ? "" : String(p[col]);
  Object.assign(initial, { orgType: s(p.org_type) === "—" ? "" : String(p.org_type), country: String(p.country ?? ""), category: String(p.category ?? ""),
    facultyCode: String(p.faculty_code ?? ""), deptCode: String(p.dept_code ?? ""), fundingStatus: String(p.funding_status ?? ""),
    budget: p.budget == null ? "" : String(p.budget), currency: String(p.currency ?? "") });
  const [v, setV] = useState(initial);
  const [reason, setReason] = useState("");
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const changed = Object.keys(v).filter((k) => v[k] !== initial[k]);
  const set = (k: string, x: string) => setV((o) => ({ ...o, [k]: x }));
  const deps = desk.departments.filter((x) => !v.facultyCode || x.faculty_code === v.facultyCode);

  async function save() {
    setBusy(true); setProblem(null);
    const answers: Record<string, string> = {};
    for (const k of changed) answers[k] = k === "budget" ? v[k].replace(/[,\s]/g, "") : v[k];
    try {
      const r = await ptnCall(`/${p.id}`, { method: "PUT", body: { answers, reason }, reason: `Partnership record corrected: ${p.reference}` });
      if (!r.ok) { setProblem(r.problem); return; }
      await onDone();
    } finally { setBusy(false); }
  }
  const sel = (k: string, label: string, opts: [string, string][], none = "Choose…") => (
    <Field id={`ed-${k}`} label={label}><select id={`ed-${k}`} className="ctl" value={v[k]} onChange={(e) => set(k, e.target.value)}><option value="">{none}</option>{opts.map(([a, b]) => <option key={a} value={a}>{b}</option>)}</select></Field>
  );

  return (
    <Modal wide title="Correct the record" sub={`${p.reference}: only what you change is saved, with the reason, on the timeline. The applicant's declarations are never changed.`} onClose={onClose}
      foot={<><Btn kind="ghost" onClick={onClose}>Cancel</Btn><span className="grow" /><span className="sub2">{changed.length ? `${changed.length} change${changed.length === 1 ? "" : "s"}` : "No changes"}</span>
        <Btn kind="primary" busy={busy} busyLabel="Saving…" disabled={!changed.length || reason.trim().length < 5} onClick={() => void save()}>Save</Btn></>}>
      <div className="grid grid--2">
        {EDITABLE.map(([k, , label, kind]) => (
          <Field key={k} id={`ed-${k}`} label={label} full={kind === "area"}>
            {kind === "area" ? <textarea id={`ed-${k}`} className="ctl" rows={3} value={v[k]} onChange={(e) => set(k, e.target.value)} />
              : <input id={`ed-${k}`} type={kind === "email" ? "email" : "text"} className="ctl" value={v[k]} onChange={(e) => set(k, e.target.value)} />}
          </Field>
        ))}
        {sel("orgType", "Organisation type", ORG_TYPES)}
        {sel("country", "Country", countries().map((c) => [c, c]))}
        <Field id="ed-category" label="Category">
          <select id="ed-category" className="ctl" value={v.category} onChange={(e) => set("category", e.target.value)}>
            {desk.groups.map((g) => <optgroup key={g.code} label={g.label}>{desk.categories.filter((c) => c.grp === g.code).map((c) => <option key={c.code} value={c.code}>{c.label}</option>)}</optgroup>)}
          </select>
        </Field>
        {sel("facultyCode", "Faculty", desk.faculties.map((x) => [x.code, x.name]), "None")}
        {sel("deptCode", "Department", deps.map((x) => [x.code, x.name]), "None")}
        {sel("fundingStatus", "Funding", FUNDING)}
        <Field id="ed-budget" label="Estimated budget"><input id="ed-budget" inputMode="decimal" className="ctl" value={v.budget} onChange={(e) => set("budget", e.target.value)} /></Field>
        {sel("currency", "Currency", CURRENCIES.map((c) => [c, c]), "None")}
        <Field id="ed-reason" label="Reason for the correction" required full hint="5 characters at least: what was wrong and where the right answer came from">
          <input id="ed-reason" className="ctl" value={reason} onChange={(e) => setReason(e.target.value)} />
        </Field>
      </div>
      {problem ? <ProblemNotice problem={problem} /> : null}
    </Modal>
  );
}
