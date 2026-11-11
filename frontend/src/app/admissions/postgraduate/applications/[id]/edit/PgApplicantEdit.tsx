"use client";

/**
 * V715: the postgraduate applicant's record — read whole and corrected from one place by the School of Postgraduate Studies and
 * the Director of ICT. The identity, contacts, programme, session and previous education are saved here in one transaction
 * (PUT …/edit), each save on the reading the page was made from, with a reason, the changes reviewed and confirmed first; the
 * previous degrees as one change. The state, the fees, the screening and the decisions keep their own workflows, linked from here;
 * once the applicant is on the register, the student's record is corrected on the student edit page (V642).
 */
import { useRouter } from "next/navigation";
import { useMemo, useState, type ReactNode } from "react";
import Link from "next/link";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, KvGrid, LinkBtn, Note, Panel, PBody, Pil, Tabs } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { reasonProblem } from "@/lib/student-edit";
import {
  PRIOR_KIND_WORD, awardWord, fieldWord, stateWord, words,
  type EditPage, type HistoryRow, type PgPermission, type PriorDegree,
} from "@/lib/pg-records";

type Section = "basic" | "contact" | "programme" | "education" | "documents" | "admission" | "fees" | "history";
const SECTIONS: [Section, string][] = [
  ["basic", "Basic information"], ["contact", "Contact information"], ["programme", "Application & programme"], ["education", "Previous education"],
  ["documents", "Documents & referees"], ["admission", "Screening & admission"], ["fees", "Fees"], ["history", "Change history"],
];

type Answer<T> = { ok: true; data: T } | { ok: false; problem: Problem & { code?: string } };

async function call<T>(method: string, path: string, body: unknown, reason: string): Promise<Answer<T>> {
  const r = await fetch(`/api/bff${path}`, {
    method, cache: "no-store",
    headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) },
    body: method === "GET" ? undefined : JSON.stringify(body ?? {}),
  });
  const j = await r.json().catch(() => null);
  return r.ok ? { ok: true, data: j as T } : { ok: false, problem: (j && typeof j === "object" && "status" in j ? j : { status: r.status, title: r.statusText }) as Problem };
}

const day = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—");
const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");
const naira = (v: number | string | null | undefined) => (v == null ? "—" : `₦${Number(v).toLocaleString("en-NG", { minimumFractionDigits: 2 })}`);
const CRITICAL = ["email", "programme_code", "session"];

type May = (p: PgPermission) => boolean;
type Settle = <T>(r: Answer<T>, done: (d: T) => void) => boolean;

export function PgApplicantEdit({ page, initialSection }: { page: EditPage; initialSection?: string | null }) {
  const router = useRouter();
  const a = page.application;
  const may: May = (p) => page.permissions.includes(p);
  const [section, setSection] = useState<Section>(SECTIONS.some(([k]) => k === initialSection) ? (initialSection as Section) : "basic");
  const [stale, setStale] = useState(false);
  const name = `${a.surname}${a.other_names ? `, ${a.other_names}` : ""}`;

  function choose(k: Section) {
    setSection(k);
    try {
      const u = new URL(window.location.href);
      u.searchParams.set("section", k);
      window.history.replaceState(window.history.state, "", u.toString());
    } catch { /* the address stays */ }
  }

  const settle: Settle = (r, done) => {
    if (r.ok) { done(r.data); router.refresh(); return true; }
    if (r.problem.code === "PG_EDIT_STALE") setStale(true);
    notifyProblem(r.problem);
    return false;
  };

  const summary: [ReactNode, ReactNode][] = [
    ["Qualification", awardWord(a.award)], ["Programme", a.programme], ["Specialisation", a.specialisation ?? "—"],
    ["Department", a.department ?? "—"], ["Faculty", a.faculty ?? "—"], ["Session", a.session],
    ["Entry level", `${a.entry_level}`], ["Application state", stateWord(a.state)],
    ["Documents", a.documents_state ? `${words(a.documents_state)} · ${a.documents_uploaded ?? 0}/${a.documents_required ?? 0}` : "—"],
    ["On the register", page.student ? `${page.student.admission_no ?? "—"}${page.student.matric_no ? ` · ${page.student.matric_no}` : ""}` : "Not yet"],
  ];

  return (
    <>
      <Panel title={<span>Postgraduate record · <span className="tnum">{a.application_no}</span>{a.legacy_application_no ? <span className="sub2"> · old portal {a.legacy_application_no}</span> : null}</span>}
        right={<span className="row row--inline row--tight">
          <LinkBtn kind="ghost" href={`/admissions/postgraduate/applications/${a.id}`}>Application desk</LinkBtn>
          {page.student ? <LinkBtn kind="ghost" href={`/students/${page.student.id}/edit`}>Student edit page</LinkBtn> : null}
          <LinkBtn kind="ghost" href="/admissions/postgraduate/records">Another record</LinkBtn>
        </span>}>
        <PBody>
          <div className="row" style={{ alignItems: "baseline", flexWrap: "wrap", gap: "var(--s-3)" }}>
            <b style={{ fontSize: "1.15rem" }}>{name}</b>
            <span className="sub2 tnum">{a.email} · {a.phone ?? "no phone"} · applied {day(a.submitted_at ?? a.created_at)}</span>
            <Pil kind={["OFFERED", "ACCEPTED", "ADMITTED"].includes(a.state) ? "ok" : ["NOT_OFFERED", "DEPT_DECLINED", "FAC_DECLINED"].includes(a.state) ? "bad" : "info"}>{stateWord(a.state)}</Pil>
          </div>
          {page.student ? (
            <Note kind="info" title="This applicant is on the University register">
              Their names, programme, level, status and matriculation are the student&rsquo;s record now, corrected on the
              <Link href={`/students/${page.student.id}/edit`}> student edit page</Link> ({page.student.admission_no ?? page.student.matric_no}
              {page.student.stage ? ` · ${page.student.stage}` : ""} · {words(page.student.status)}). The contacts and previous education of the application are still corrected here.
            </Note>
          ) : null}
          <div className="mt-3"><KvGrid cls="grid--5" pairs={summary} /></div>
        </PBody>
      </Panel>

      {stale ? (
        <Note kind="bad" title="This record was updated by another user" action={<Btn kind="primary" onClick={() => { setStale(false); router.refresh(); }}>Refresh the record</Btn>}>
          Refresh the record before saving your changes. Nothing you were saving was written.
        </Note>
      ) : null}

      <div style={{ maxWidth: "100%", overflowX: "auto" }}>
        <Tabs look="line" label="Sections of the record" value={section} onChange={choose} items={SECTIONS.map(([id, label]) => ({ id, label }))} />
      </div>

      {section === "basic" ? <FieldsSection key={page.version} page={page} may={may} settle={settle} title="Basic information" perm="EDIT_PG_BIODATA" onRegister={!!page.student}
        fields={[["surname", "text"], ["other_names", "text"], ["sex", "sex"], ["date_of_birth", "date"], ["state_of_origin", "text"], ["lga", "text"], ["nationality", "text"]]}
        note="A name, sex or date of birth corrected here is kept with its reason. Once the applicant is on the register, these are the student's and are corrected on the student edit page." /> : null}
      {section === "contact" ? <FieldsSection key={page.version} page={page} may={may} settle={settle} title="Contact information" perm="EDIT_PG_BIODATA" onRegister={false}
        fields={[["email", "text"], ["phone", "text"], ["contact_address", "area"]]}
        note="The e-mail is the one the applicant signs in with: changing it is a critical change, confirmed before it is saved. A phone is eleven digits (0…) or +234…." /> : null}
      {section === "programme" ? <ProgrammeSection key={page.version} page={page} may={may} settle={settle} /> : null}
      {section === "education" ? <EducationSection key={page.version} page={page} may={may} settle={settle} /> : null}
      {section === "documents" ? <DocumentsSection key={page.version} page={page} may={may} /> : null}
      {section === "admission" ? <AdmissionSection page={page} /> : null}
      {section === "fees" ? <FeesSection page={page} /> : null}
      {section === "history" ? <HistorySection page={page} may={may} /> : null}
    </>
  );
}

/* ── the reason, the evidence and — for a critical change — the review and the officer's confirmation ── */

function ReasonBox({ id, reason, setReason, evidence, setEvidence }: { id: string; reason: string; setReason: (v: string) => void; evidence?: string; setEvidence?: (v: string) => void }) {
  const problem = reason.trim() ? reasonProblem(reason) : null;
  return (
    <div className="grid grid--2">
      <Field id={`${id}-reason`} label="Reason for change" required error={problem}
        hint="What was wrong, and where the right value comes from — the document, the list or the decision. Kept on the record's history.">
        <textarea id={`${id}-reason`} className="ctl" rows={2} value={reason} onChange={(e) => setReason(e.target.value)}
          placeholder="Corrected the surname to the one on the degree certificate presented at screening." />
      </Field>
      {setEvidence ? (
        <Field id={`${id}-ev`} label="Evidence" hint="Optional: the document, reference or ticket the correction rests on">
          <input id={`${id}-ev`} className="ctl" value={evidence ?? ""} onChange={(e) => setEvidence(e.target.value)} placeholder="Degree certificate · ticket HD/2026/000123" />
        </Field>
      ) : null}
    </div>
  );
}

function diff(now: Record<string, string>, was: Record<string, string>) {
  const out: Record<string, string> = {};
  for (const k of Object.keys(now)) if ((now[k] ?? "").trim() !== (was[k] ?? "").trim()) out[k] = now[k].trim();
  return out;
}

/** the changes reviewed before they are saved: each field, the value before and after; a critical one confirmed */
function Review({ changes, was, labels, reason, onCancel, onConfirm, busy }: {
  changes: Record<string, string>; was: Record<string, string>; labels: (k: string, v: string) => string; reason: string; onCancel: () => void; onConfirm: (confirmed: boolean) => void; busy: boolean;
}) {
  const critical = Object.keys(changes).some((k) => CRITICAL.includes(k));
  const [confirmed, setConfirmed] = useState(false);
  return (
    <Modal title="Review changes" sub="What will be written, before it is" onClose={onCancel}
      foot={<div className="row"><Btn kind="ghost" onClick={onCancel} disabled={busy}>Cancel</Btn>
        <Btn kind="primary" busy={busy} busyLabel="Saving…" disabled={critical && !confirmed} onClick={() => onConfirm(confirmed)}>Confirm changes</Btn></div>}>
      <DTable pageSize={0} cols={["Field", "Old", "New"]} rows={Object.keys(changes).map((k) => [
        <span key="f">{fieldWord(k)}{CRITICAL.includes(k) ? <Pil kind="bad"> critical</Pil> : null}</span>,
        <span key="o" className="sub2">{labels(k, was[k] ?? "") || "—"}</span>, <b key="n">{labels(k, changes[k]) || "—"}</b>,
      ])} />
      <div className="mt-2 sub2">Reason: {reason}</div>
      {critical ? (
        <label className="row row--inline mt-2" style={{ gap: "var(--s-2)" }}>
          <input type="checkbox" checked={confirmed} onChange={(e) => setConfirmed(e.target.checked)} />
          <span><b>This is a critical change.</b> I have checked it against the University&rsquo;s documents and accept that it is kept in my name.</span>
        </label>
      ) : null}
    </Modal>
  );
}

function useFieldEdit(page: EditPage, settle: Settle) {
  const [busy, setBusy] = useState(false);
  async function save(changes: Record<string, string>, reason: string, confirmCritical: boolean, evidence: string, what: string) {
    setBusy(true);
    try {
      const r = await call<{ changed: number; edits: { field: string; reference: string }[] }>("PUT", `/api/v1/pg/records/applications/${page.application.id}/edit`,
        { changes, reason: reason.trim(), version: page.version, confirmCritical, evidence: evidence || null }, `${what} corrected on the postgraduate record page`);
      return settle(r, (d) => notify(`${d.changed} change${d.changed === 1 ? "" : "s"} saved · ${d.edits.map((e) => e.reference).join(", ")}`));
    } finally {
      setBusy(false);
    }
  }
  return { busy, save };
}

/* ── a section of plain fields: basic information, contact information ── */

type FieldKind = "text" | "date" | "sex" | "area";

function FieldsSection({ page, may, settle, title, perm, fields, note, onRegister }: {
  page: EditPage; may: May; settle: Settle; title: string; perm: PgPermission; fields: [string, FieldKind][]; note: string; onRegister: boolean;
}) {
  const a = page.application as unknown as Record<string, string | null>;
  const was = useMemo(() => Object.fromEntries(fields.map(([k]) => [k, a[k] ?? ""])) as Record<string, string>, [a, fields]);
  const [f, setF] = useState(was);
  const [reason, setReason] = useState("");
  const [evidence, setEvidence] = useState("");
  const [review, setReview] = useState(false);
  const { busy, save } = useFieldEdit(page, settle);
  const changes = diff(f, was);
  const can = may(perm) && !onRegister;
  return (
    <Panel title={title} right={<span className="sub2">{onRegister ? "On the register: the student's, corrected on the student edit page" : "Saved together, with a reason"}</span>}>
      <PBody>
        {!may(perm) ? <Note kind="info" title="Read only">Your office does not hold {perm}.</Note> : null}
        <div className="grid grid--4">
          {fields.map(([k, kind]) => (
            <Field key={k} id={`pf-${k}`} label={fieldWord(k)} full={kind === "area"}>
              {kind === "sex" ? (
                <select id={`pf-${k}`} className="ctl" disabled={!can} value={f[k]} onChange={(e) => setF({ ...f, [k]: e.target.value })}>
                  <option value="">—</option><option value="F">Female</option><option value="M">Male</option>
                </select>
              ) : kind === "area" ? (
                <textarea id={`pf-${k}`} className="ctl" rows={2} disabled={!can} value={f[k]} onChange={(e) => setF({ ...f, [k]: e.target.value })} />
              ) : (
                <input id={`pf-${k}`} type={kind === "date" ? "date" : "text"} className="ctl" disabled={!can} value={f[k]} onChange={(e) => setF({ ...f, [k]: e.target.value })} />
              )}
            </Field>
          ))}
        </div>
        {can && Object.keys(changes).length ? <ReasonBox id={`pf-${perm}`} reason={reason} setReason={setReason} evidence={evidence} setEvidence={setEvidence} /> : null}
        {can ? (
          <div className="row mt-2">
            <Btn kind="primary" disabled={!Object.keys(changes).length || !!reasonProblem(reason) || busy} onClick={() => setReview(true)}>Review and save</Btn>
            <span className="sub2">{note}</span>
          </div>
        ) : null}
        {review ? <Review changes={changes} was={was} labels={(k, v) => (k === "sex" ? (v === "F" ? "Female" : v === "M" ? "Male" : v) : v)} reason={reason} busy={busy}
          onCancel={() => setReview(false)} onConfirm={async (ok) => { if (await save(changes, reason, ok, evidence, title)) { setReview(false); setReason(""); } }} /> : null}
      </PBody>
    </Panel>
  );
}

/* ── the programme: faculty → department → programme → specialisation, the session; the level follows the programme ── */

function ProgrammeSection({ page, may, settle }: { page: EditPage; may: May; settle: Settle }) {
  const a = page.application;
  const L = page.lists;
  const was = useMemo(() => ({ programme_code: a.programme_code, specialisation_id: a.specialisation_id ?? "", session: a.session }), [a]);
  const [faculty, setFaculty] = useState(a.faculty_code ?? "");
  const [dept, setDept] = useState(a.dept_code ?? "");
  const [f, setF] = useState(was);
  const [specs, setSpecs] = useState(page.specialisations);
  const [reason, setReason] = useState("");
  const [evidence, setEvidence] = useState("");
  const [review, setReview] = useState(false);
  const { busy, save } = useFieldEdit(page, settle);
  const canProg = may("EDIT_PG_PROGRAMME") && !page.student && !a.student_id && !a.spgs_decided_at;   // V721: on the register, the student edit page
  const canSession = may("EDIT_PG_ADMISSION") && !page.student && !a.student_id && !page.fees.some((x) => x.confirmed_at);
  const departments = L.departments.filter((d) => !faculty || d.faculty_code === faculty);
  const programmes = L.programmes.filter((p) => (!faculty || p.faculty_code === faculty) && (!dept || p.dept_code === dept));
  const changes = diff(f, was);
  const prog = L.programmes.find((p) => p.code === f.programme_code);
  async function chooseProgramme(code: string) {
    setF({ ...f, programme_code: code, specialisation_id: "" });
    if (!code || code === a.programme_code) { setSpecs(page.specialisations); return; }
    const r = await call<{ id: string; code: string; name: string }[]>("GET", `/api/v1/pg/records/programmes/${encodeURIComponent(code)}/specialisations`, null, "");
    setSpecs(r.ok ? r.data : []);
  }
  const labels = (k: string, v: string) => k === "programme_code" ? (L.programmes.find((p) => p.code === v)?.name ?? v)
    : k === "specialisation_id" ? ([...specs, ...page.specialisations].find((s) => s.id === v)?.name ?? (v ? v : "none")) : v;
  return (
    <>
      <Panel title="Application and programme" right={<span className="sub2">The application number never changes</span>}>
        <PBody>
          <KvGrid cls="grid--4" pairs={[["Application number", <span key="n" className="tnum">{a.application_no}</span>], ["Old portal number", a.legacy_application_no ?? "—"],
            ["Applied", day(a.submitted_at ?? a.created_at)], ["State", stateWord(a.state)], ["Qualification", awardWord(a.award)], ["Entry level", `${a.entry_level}`],
            ["Research degree", a.research ? "Yes" : "No"], ["Research proposal", a.proposal_title ?? "—"]]} />
          {page.student ? (
            <Note kind="info" title="On the register"
              action={a.student_id ? <LinkBtn kind="primary" size="sm" href={`/students/${a.student_id}/edit?section=placement`}>Change the programme on the student edit page</LinkBtn> : undefined}>
              The programme and the session are the student&rsquo;s now: the programme is changed by the programme swap on the student edit page (V719: the School, for a postgraduate student),
              where the admission record follows and the history is kept.
            </Note>)
            : a.spgs_decided_at ? <Note kind="info" title="Decided by the School">The School decided this application on {day(a.spgs_decided_at)} for {a.programme}. The programme is corrected before the decision, or by the programme swap once the applicant is on the register; return the application to change the decision.</Note>
            : !may("EDIT_PG_PROGRAMME") ? <Note kind="info" title="Read only">Your office does not hold EDIT_PG_PROGRAMME.</Note> : null}
          <div className="grid grid--4 mt-2">
            <Field id="pp-fac" label="Faculty">
              <select id="pp-fac" className="ctl" disabled={!canProg} value={faculty} onChange={(e) => { setFaculty(e.target.value); setDept(""); void chooseProgramme(""); }}>
                <option value="">Any</option>{L.faculties.map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}
              </select>
            </Field>
            <Field id="pp-dept" label="Department">
              <select id="pp-dept" className="ctl" disabled={!canProg} value={dept} onChange={(e) => { setDept(e.target.value); void chooseProgramme(""); }}>
                <option value="">Any</option>{departments.map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}
              </select>
            </Field>
            <Field id="pp-prog" label="Programme" hint={prog ? `${awardWord(prog.award)} · the entry level follows the programme` : "Postgraduate programmes in use"}>
              <select id="pp-prog" className="ctl" disabled={!canProg} value={f.programme_code} onChange={(e) => void chooseProgramme(e.target.value)}>
                <option value="">Choose the programme</option>{programmes.map((x) => <option key={x.code} value={x.code}>{x.name}</option>)}
              </select>
            </Field>
            <Field id="pp-spec" label="Specialisation" hint={specs.length ? "The programme's running specialisations" : "None runs on this programme"}>
              <select id="pp-spec" className="ctl" disabled={!canProg || !specs.length} value={f.specialisation_id} onChange={(e) => setF({ ...f, specialisation_id: e.target.value })}>
                <option value="">None</option>{specs.map((s) => <option key={s.id} value={s.id}>{s.name}</option>)}
              </select>
            </Field>
            <Field id="pp-ses" label="Session" hint={canSession ? "A critical change" : page.fees.some((x) => x.confirmed_at) ? "A fee was paid for the session: the Bursary's reallocation moves a payment" : undefined}>
              <select id="pp-ses" className="ctl" disabled={!canSession} value={f.session} onChange={(e) => setF({ ...f, session: e.target.value })}>
                {L.sessions.map((s) => <option key={s.name} value={s.name}>{s.name}{s.state === "CURRENT" ? " (current)" : ""}</option>)}
              </select>
            </Field>
          </div>
          {(canProg || canSession) && Object.keys(changes).length ? <ReasonBox id="pp" reason={reason} setReason={setReason} evidence={evidence} setEvidence={setEvidence} /> : null}
          {canProg || canSession ? (
            <div className="row mt-2">
              <Btn kind="primary" disabled={!Object.keys(changes).length || !f.programme_code || !!reasonProblem(reason) || busy} onClick={() => setReview(true)}>Review and save</Btn>
              <span className="sub2">A programme corrected here is a data correction before the School decides; an actual change of programme after admission is the programme swap, which keeps the history.</span>
            </div>
          ) : null}
          {review ? <Review changes={changes} was={was} labels={labels} reason={reason} busy={busy} onCancel={() => setReview(false)}
            onConfirm={async (ok) => { if (await save(changes, reason, ok, evidence, "Programme")) { setReview(false); setReason(""); } }} /> : null}
        </PBody>
      </Panel>
    </>
  );
}

/* ── previous education: the first degree on the application, and every previous degree ── */

function EducationSection({ page, may, settle }: { page: EditPage; may: May; settle: Settle }) {
  const a = page.application;
  const was = useMemo(() => ({ prior_institution: a.prior_institution ?? "", prior_award: a.prior_award ?? "", prior_class: a.prior_class ?? "",
    prior_cgpa: a.prior_cgpa == null ? "" : String(a.prior_cgpa), prior_year: a.prior_year == null ? "" : String(a.prior_year), proposal_title: a.proposal_title ?? "" }), [a]);
  const [f, setF] = useState(was);
  const [reason, setReason] = useState("");
  const [review, setReview] = useState(false);
  const { busy, save } = useFieldEdit(page, settle);
  const changes = diff(f, was);
  const can = may("EDIT_PG_APPLICANT");
  const blank = (): PriorDegree => ({ kind: "FIRST", institution: "", award: "", field: "", class_of_degree: "", cgpa: "", year: null });
  const [degrees, setDegrees] = useState<PriorDegree[]>(page.priorDegrees.map((d) => ({ ...d })));
  const [dReason, setDReason] = useState("");
  const [dBusy, setDBusy] = useState(false);
  const plain = (d: PriorDegree) => [d.kind, d.institution, d.award, d.field ?? "", d.class_of_degree ?? "", d.cgpa == null ? "" : String(d.cgpa), d.year == null ? "" : String(d.year)];
  const degreesChanged = JSON.stringify(degrees.map(plain)) !== JSON.stringify(page.priorDegrees.map(plain));
  async function saveDegrees() {
    setDBusy(true);
    try {
      const rows = degrees.map((d) => ({ kind: d.kind, institution: d.institution, award: d.award, field: d.field ?? "", class_of_degree: d.class_of_degree ?? "",
        cgpa: d.cgpa == null ? "" : String(d.cgpa), year: d.year == null ? "" : String(d.year) }));
      const r = await call<{ degrees: number; reference: string }>("PUT", `/api/v1/pg/records/applications/${a.id}/edit/prior-degrees`,
        { rows, reason: dReason.trim(), version: page.version }, "Previous degrees corrected on the postgraduate record page");
      if (settle(r, (d) => notify(`${d.degrees} previous degree${d.degrees === 1 ? "" : "s"} saved · ${d.reference}`))) setDReason("");
    } finally {
      setDBusy(false);
    }
  }
  const set = (i: number, patch: Partial<PriorDegree>) => setDegrees(degrees.map((d, j) => (j === i ? { ...d, ...patch } : d)));
  return (
    <>
      <Panel title="First degree and research proposal" right={<span className="sub2">As the application states them</span>}>
        <PBody>
          {!can ? <Note kind="info" title="Read only">Your office does not hold EDIT_PG_APPLICANT.</Note> : null}
          <div className="grid grid--3">
            <Field id="pe-inst" label={fieldWord("prior_institution")}><input id="pe-inst" className="ctl" disabled={!can} value={f.prior_institution} onChange={(e) => setF({ ...f, prior_institution: e.target.value })} /></Field>
            <Field id="pe-aw" label={fieldWord("prior_award")}><input id="pe-aw" className="ctl" disabled={!can} value={f.prior_award} onChange={(e) => setF({ ...f, prior_award: e.target.value })} placeholder="B.Sc. Computer Science" /></Field>
            <Field id="pe-cl" label={fieldWord("prior_class")}><input id="pe-cl" className="ctl" disabled={!can} value={f.prior_class} onChange={(e) => setF({ ...f, prior_class: e.target.value })} placeholder="Second Class Upper" /></Field>
            <Field id="pe-cg" label={fieldWord("prior_cgpa")} hint="0.00 to 5.00"><input id="pe-cg" className="ctl tnum" disabled={!can} value={f.prior_cgpa} onChange={(e) => setF({ ...f, prior_cgpa: e.target.value })} /></Field>
            <Field id="pe-yr" label={fieldWord("prior_year")}><input id="pe-yr" className="ctl tnum" disabled={!can} value={f.prior_year} onChange={(e) => setF({ ...f, prior_year: e.target.value })} /></Field>
            <Field id="pe-pt" label={fieldWord("proposal_title")}><input id="pe-pt" className="ctl" disabled={!can} value={f.proposal_title} onChange={(e) => setF({ ...f, proposal_title: e.target.value })} /></Field>
          </div>
          {can && Object.keys(changes).length ? <ReasonBox id="pe" reason={reason} setReason={setReason} /> : null}
          {can ? <div className="row mt-2"><Btn kind="primary" disabled={!Object.keys(changes).length || !!reasonProblem(reason) || busy} onClick={() => setReview(true)}>Review and save</Btn></div> : null}
          {review ? <Review changes={changes} was={was} labels={(_k, v) => v} reason={reason} busy={busy} onCancel={() => setReview(false)}
            onConfirm={async (ok) => { if (await save(changes, reason, ok, "", "Previous education")) { setReview(false); setReason(""); } }} /> : null}
        </PBody>
      </Panel>
      <Panel title="Previous degrees" right={can ? <Btn kind="secondary" size="sm" onClick={() => setDegrees([...degrees, blank()])}>+ Add a degree</Btn> : `${degrees.length}`}>
        <PBody>
          {!degrees.length ? <div className="sub2">No previous degree is recorded beside the first degree above.</div> : null}
          {degrees.map((d, i) => (
            <div key={d.id ?? `new-${i}`} className="grid grid--4" style={{ alignItems: "end" }}>
              <Field id={`pd-k-${i}`} label="Kind">
                <select id={`pd-k-${i}`} className="ctl" disabled={!can} value={d.kind} onChange={(e) => set(i, { kind: e.target.value })}>
                  {page.priorKinds.map((k) => <option key={k} value={k}>{PRIOR_KIND_WORD[k] ?? k}</option>)}
                </select>
              </Field>
              <Field id={`pd-i-${i}`} label="Institution"><input id={`pd-i-${i}`} className="ctl" disabled={!can} value={d.institution} onChange={(e) => set(i, { institution: e.target.value })} /></Field>
              <Field id={`pd-a-${i}`} label="Award"><input id={`pd-a-${i}`} className="ctl" disabled={!can} value={d.award} onChange={(e) => set(i, { award: e.target.value })} /></Field>
              <Field id={`pd-f-${i}`} label="Field of study"><input id={`pd-f-${i}`} className="ctl" disabled={!can} value={d.field ?? ""} onChange={(e) => set(i, { field: e.target.value })} /></Field>
              <Field id={`pd-c-${i}`} label="Class of degree"><input id={`pd-c-${i}`} className="ctl" disabled={!can} value={d.class_of_degree ?? ""} onChange={(e) => set(i, { class_of_degree: e.target.value })} /></Field>
              <Field id={`pd-g-${i}`} label="CGPA"><input id={`pd-g-${i}`} className="ctl tnum" disabled={!can} value={d.cgpa == null ? "" : String(d.cgpa)} onChange={(e) => set(i, { cgpa: e.target.value })} /></Field>
              <Field id={`pd-y-${i}`} label="Year"><input id={`pd-y-${i}`} className="ctl tnum" disabled={!can} value={d.year == null ? "" : String(d.year)} onChange={(e) => set(i, { year: e.target.value ? Number(e.target.value) : null })} /></Field>
              {can ? <div><Btn kind="ghost" size="sm" onClick={() => setDegrees(degrees.filter((_x, j) => j !== i))}>Remove</Btn></div> : null}
            </div>
          ))}
          {can && degreesChanged ? <ReasonBox id="pd" reason={dReason} setReason={setDReason} /> : null}
          {can ? (
            <div className="row mt-2">
              <Btn kind="primary" busy={dBusy} busyLabel="Saving…" disabled={!degreesChanged || !!reasonProblem(dReason)} onClick={() => void saveDegrees()}>Save previous degrees</Btn>
              <span className="sub2">The list is saved as one change: the degrees before and after are kept on the history.</span>
            </div>
          ) : null}
        </PBody>
      </Panel>
    </>
  );
}

/* ── documents and referees: read here, managed where they are ── */

const DESK_DOC_KINDS = ["TRANSCRIPT", "DEGREE_CERTIFICATE", "HIGHER_DEGREE", "UNDERGRAD_CERT", "OLEVEL", "CV", "PROPOSAL", "NYSC", "BIRTH_CERTIFICATE", "LGA_CERTIFICATE", "NAME_CHANGE", "CREDENTIALS", "OTHER"];

function DocumentsSection({ page, may }: { page: EditPage; may: May }) {
  const a = page.application;
  const router = useRouter();
  const canUpload = may("EDIT_PG_RECORD");
  const [kind, setKind] = useState("TRANSCRIPT");
  const [file, setFile] = useState<File | null>(null);
  const [why, setWhy] = useState("");
  const [up, setUp] = useState(false);
  /* V721: the desk uploads a document the applicant could not, or replaces a wrong one — the one of that kind is replaced (a
     higher-degree certificate is added), the upload kept on the application's history with the reason */
  async function upload() {
    if (!file) return;
    setUp(true);
    try {
      const base64 = await new Promise<string>((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(String(reader.result).split(",")[1] ?? "");
        reader.onerror = () => reject(reader.error);
        reader.readAsDataURL(file);
      });
      const r = await call<{ replaced: string | null; filename: string }>("POST", `/api/v1/pg/records/applications/${a.id}/documents`,
        { kind, filename: file.name, contentType: file.type || "application/octet-stream", base64, reason: why.trim() || null }, `Document ${kind} uploaded by the desk for ${a.application_no}`);
      if (r.ok) { notify(`${r.data.filename} uploaded${r.data.replaced ? ` (replacing ${r.data.replaced})` : ""}`); setFile(null); setWhy(""); router.refresh(); }
      else notifyProblem(r.problem);
    } finally { setUp(false); }
  }
  return (
    <>
      {canUpload ? (
        <Panel title="Upload or replace a document" right={<span className="sub2">By the desk, kept on the application&rsquo;s history</span>}>
          <PBody>
            <div className="grid grid--3">
              <Field id="pd-kind" label="Document">
                <select id="pd-kind" className="ctl" value={kind} onChange={(e) => setKind(e.target.value)}>{DESK_DOC_KINDS.map((k) => <option key={k} value={k}>{words(k)}</option>)}</select>
              </Field>
              <Field id="pd-file" label="File" hint="PDF or image, up to 8 MB; the document of that kind is replaced (a higher-degree certificate is added)">
                <input id="pd-file" type="file" className="ctl" accept=".pdf,.jpg,.jpeg,.png" onChange={(e) => setFile(e.target.files?.[0] ?? null)} />
              </Field>
              <Field id="pd-why" label="Note (optional)" hint="Why the desk uploads it — e.g. brought to the School in person">
                <input id="pd-why" className="ctl" value={why} onChange={(e) => setWhy(e.target.value)} />
              </Field>
            </div>
            <div className="row mt-2"><Btn kind="primary" busy={up} busyLabel="Uploading…" disabled={!file} onClick={() => void upload()}>Upload the document</Btn></div>
          </PBody>
        </Panel>
      ) : null}
      <Panel title="Documents" right={<span className="sub2">{a.documents_state ? `${words(a.documents_state)} · ${a.documents_uploaded ?? 0} of ${a.documents_required ?? 0}` : ""}</span>}>
        <PBody>
          <div className="sub2">The applicant uploads their documents on the applicant portal; the School reads and prints them from the application desk. A document is never deleted here; the old portal&rsquo;s are attached on the legacy migration desk.</div>
          {a.documents_missing?.length ? <div className="mt-2">Missing: {a.documents_missing.map((m) => words(m)).join(", ")}</div> : null}
        </PBody>
        {page.documents.length ? <DTable pageSize={0} cols={["Document", "File", "Uploaded", "|num"]} rows={page.documents.map((d) => [
          words(d.kind), d.filename, <span key="u" className="tnum">{when(d.uploaded_at)}</span>,
          <a key="o" className="btn btn--ghost btn--sm" href={`/api/bff/api/v1/pg/applications/${a.id}/documents/${d.id}`} target="_blank" rel="noreferrer">Open</a>,
        ])} /> : null}
        {page.legacyDocuments.length ? <DTable pageSize={0} cols={["Old portal document", "Reference", "Attached"]} rows={page.legacyDocuments.map((d) => [
          d.label, <span key="r" className="tnum">{d.legacy_ref ?? "—"}</span>, d.attached_at ? when(d.attached_at) : <Pil kind="warn">Not yet attached</Pil>,
        ])} /> : null}
      </Panel>
      <Panel title="Referees" right={`${page.referees.length}`}>
        {page.referees.length ? <DTable pageSize={0} cols={["Referee", "Institution", "Contact", "Reference|mid"]} rows={page.referees.map((r) => [
          <span key="n"><b>{r.name}</b>{r.position ? <span className="sub2"> · {r.position}</span> : null}</span>, r.institution ?? "—",
          <span key="c" className="sub2">{r.email ?? "—"}{r.phone ? ` · ${r.phone}` : ""}</span>,
          r.submitted_at ? <Pil key="v" kind={r.verdict === "DO_NOT_RECOMMEND" ? "bad" : "ok"}>{words(r.verdict) }</Pil> : <Pil key="v" kind="grey">Awaited</Pil>,
        ])} /> : <PBody><div className="sub2">No referee is named on the application.</div></PBody>}
      </Panel>
    </>
  );
}

/* ── screening and admission: read here, decided on the application desk ── */

function AdmissionSection({ page }: { page: EditPage }) {
  const a = page.application;
  const sc = page.screening;
  const steps: [string, string | null, string | null][] = [
    ["Submitted", a.submitted_at, null], ["Application fee", a.fee_confirmed_at, null], ["Department", a.dept_decided_at, a.dept_note], ["Faculty", a.fac_decided_at, a.fac_note],
    ["School of Postgraduate Studies", a.spgs_decided_at, a.spgs_note], ["Status checked", a.checking_confirmed_at, null], ["Acceptance fee", a.acceptance_confirmed_at, null],
    ["Offer accepted", a.accepted_at, null], ["On the register", a.admitted_at, null],
  ];
  return (
    <>
      <Panel title="Admission" right={<LinkBtn kind="primary" href={`/admissions/postgraduate/applications/${a.id}`}>Decide on the application desk</LinkBtn>}>
        <PBody>
          <Note kind="info" title="Decisions are made where they are made">
            The department&rsquo;s and faculty&rsquo;s recommendations, the School&rsquo;s decision, a return to the applicant, the acceptance and the admission to the register are made on the application desk, each
            recorded with who and when. They are not overwritten here.{a.decided_on_old_portal ? " This admission was decided on the old portal and brought over as it stood." : ""}
          </Note>
          <KvGrid cls="grid--3" pairs={steps.map(([k, at, note]) => [k, <span key={k}>{at ? <Pil kind="ok">{day(at)}</Pil> : <Pil kind="grey">Not yet</Pil>}{note ? <span className="sub2"> · {note}</span> : null}</span>])} />
          {a.returned_at ? <div className="mt-2 sub2">Returned to the {a.returned_to?.toLowerCase()} on {day(a.returned_at)}: {a.return_note}</div> : null}
        </PBody>
      </Panel>
      <Panel title="Physical screening" right={<LinkBtn kind="ghost" href="/admissions/postgraduate?tab=screening">Screening desk</LinkBtn>}>
        <PBody>
          {!page.screeningRequired ? <div className="sub2">The session&rsquo;s policy does not require physical screening.</div> : null}
          {sc ? <KvGrid cls="grid--4" pairs={[["State", <Pil key="s" kind={sc.state === "CLEARED" ? "ok" : sc.state === "NOT_CLEARED" ? "bad" : "warn"}>{words(sc.state)}</Pil>],
            ["Scheduled", sc.scheduled_for ? `${when(sc.scheduled_for)}${sc.venue ? ` · ${sc.venue}` : ""}` : "—"], ["Decided", sc.decided_at ? `${when(sc.decided_at)} · ${sc.officer ?? sc.officer_office ?? ""}` : "—"],
            ["Source", sc.source === "OLD_PORTAL" ? "The old portal" : "This portal"], ["Remarks", sc.remarks ?? "—"], ["Reason", sc.reason ?? "—"]]} />
            : <div className="sub2 mt-1">No screening record yet. A screening decision is recorded on the screening desk; CLEARED admits the applicant to the register.</div>}
        </PBody>
      </Panel>
    </>
  );
}

/* ── fees: read here; a wrong payment is the Bursary's ── */

function FeesSection({ page }: { page: EditPage }) {
  return (
    <>
      <Panel title="Application, checking and acceptance fees" right={<span className="sub2">Read only · a wrong payment is corrected by the Bursary&rsquo;s reallocation</span>}>
        {page.fees.length ? <DTable pageSize={0} cols={["Fee", "Reference", "Amount|num", "Generated", "Paid", "Channel"]} rows={page.fees.map((f) => [
          words(f.kind), <span key="r" className="tnum">{f.reference}</span>, <span key="a" className="tnum">{naira(f.amount)}</span>,
          <span key="g" className="tnum">{when(f.generated_at)}</span>, f.confirmed_at ? <Pil key="p" kind="ok">{when(f.confirmed_at)}</Pil> : <Pil key="p" kind="grey">Unpaid</Pil>, f.channel ?? "—",
        ])} /> : <PBody><div className="sub2">No fee reference has been raised on this application.</div></PBody>}
      </Panel>
      {page.legacyFees.length ? (
        <Panel title="Fees paid on the old portal" right={<LinkBtn kind="ghost" href="/admissions/postgraduate/migration?view=fees">Legacy migration desk</LinkBtn>}>
          <DTable pageSize={0} cols={["Fee", "Old reference", "Amount|num", "Paid on", "State|mid", "Note"]} rows={page.legacyFees.map((f) => [
            words(f.kind), <span key="r" className="tnum">{f.legacy_reference}</span>, <span key="a" className="tnum">{naira(f.amount)}</span>, day(f.paid_on),
            <Pil key="s" kind={f.state === "POSTED" ? "ok" : f.state === "REJECTED" ? "bad" : "warn"}>{words(f.state)}</Pil>, <span key="n" className="sub2">{f.decision_note ?? "—"}</span>,
          ])} />
        </Panel>
      ) : null}
      <Note kind="info" title="Finance is not changed from this page">
        Payment amounts, gateway transactions, receipts, refunds, wallets and the ledger are the Bursary&rsquo;s. School fees are the student&rsquo;s, on the student portal and the Bursary&rsquo;s desks once the applicant is on the register.
      </Note>
    </>
  );
}

/* ── the history: every correction, and the application's own events ── */

function HistorySection({ page, may }: { page: EditPage; may: May }) {
  const rows: HistoryRow[] = page.edits;
  if (!may("VIEW_PG_CHANGE_HISTORY")) return <Note kind="info" title="Read only">Your office does not hold VIEW_PG_CHANGE_HISTORY.</Note>;
  return (
    <Panel title="Change history" right={`${rows.length} change${rows.length === 1 ? "" : "s"}`}>
      {rows.length ? <DTable pageSize={50} cols={["Date", "User", "Section|mid", "Field", "Old value", "New value", "Reason", "Source"]} rows={rows.map((r, i) => [
        <span key="d" className="tnum">{when(r.at)}</span>,
        <span key="u">{r.by_name ?? "—"}{r.office ? <span className="sub2"> · {r.office}</span> : null}</span>,
        <Pil key="s" kind={r.severity === "CRITICAL" ? "bad" : "warn"}>{words(r.section)}</Pil>,
        <span key={`f${i}`}>{r.change_type === "EDIT" ? fieldWord(r.field) : words(r.change_type)}</span>,
        <span key="o" style={{ whiteSpace: "pre-wrap" }}>{r.old_value ?? "—"}</span>, <span key="n" style={{ whiteSpace: "pre-wrap" }}>{r.new_value ?? "—"}</span>,
        <span key="w" className="sub2">{r.reason ?? "—"}</span>, <span key="src" className="sub2">{r.reference ?? r.source}</span>,
      ])} /> : <PBody><div className="sub2">Nothing has changed on this record yet.</div></PBody>}
    </Panel>
  );
}
