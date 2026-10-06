"use client";

/** The postgraduate admissions desks (V202): the department's committee recommends a submitted
 *  application, the School of Postgraduate Studies offers or refuses, the applicant accepts, and the
 *  School admits — which puts the student on the register. Separate from the JAMB/CAPS flow. */
import { useEffect, useState, type ReactNode } from "react";
import { useRouter } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { notify , notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil, RoleLine, Tiles, Two } from "@/components/proto/ui";
import { Field, Modal } from "@/components/proto/blocks";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { docLabel } from "@/lib/pg-documents";
import { ScreeningDesk, SCREENING, when } from "./ScreeningDesk";

export interface PgRow {
  id: string; application_no: string; state: string; entry_level: number; programme_code: string;
  programme_name: string; pg_award: string | null; pg_research: boolean;
  department_name?: string | null; faculty_name?: string | null; documents?: number; references_in?: number;
  surname: string; other_names: string; email: string; phone: string | null; state_of_origin: string | null;
  prior_institution: string | null; prior_award: string | null; prior_class: string | null; prior_cgpa: number | null;
  fee_confirmed_at: string | null; submitted_at: string | null; dept_decided_at: string | null;
  spgs_decided_at: string | null; accepted_at: string | null; admitted_at: string | null; student_id: string | null;
  return_note?: string | null; returned_at?: string | null; returned_to?: string | null; screening_state?: string | null;
}
export interface PgView { session: string; counts: { total: number; submitted: number; recommended: number; faculty: number; offered: number; accepted: number; admitted: number; not_recommended?: number; returned?: number; not_offered?: number; unpaid?: number }; rows: PgRow[] }
interface Screening { state: string; venue: string | null; scheduled_for: string | null; verified_documents: string[] | null; missing_documents: string[] | null; issues: string | null; remarks: string | null; reason: string | null; decided_at: string | null; officer: string | null; officer_office: string | null }
interface Referee { id: string; name: string; email: string | null; phone: string | null; institution: string | null; position: string | null; reference_text: string | null; submitted_at: string | null; relationship: string | null; known_duration: string | null; attestation: string | null; recommendation: string | null; verdict: string | null }
const VERDICT_LABEL: Record<string, string> = { RECOMMEND: "Recommended", RECOMMEND_WITH_RESERVATION: "Recommended with reservation", DO_NOT_RECOMMEND: "Not recommended" };
interface DocMeta { id: string; kind: string; filename: string; content_type: string; uploaded_at: string }
interface PriorQual { kind: string; institution: string | null; award: string | null; field: string | null; class_of_degree: string | null; cgpa: number | null; year: number | null }
interface HistoryRow { kind: string; note: string | null; at: string; actor: string | null; actor_office: string | null }
interface Detail { found: boolean; application?: PgRow & { sex: string | null; date_of_birth: string | null; lga: string | null; nationality?: string | null; contact_address?: string | null; prior_year: number | null; proposal_title: string | null; proposal_text: string | null; dept_note: string | null; fac_note: string | null; fac_decided_at: string | null; spgs_note: string | null; checking_confirmed_at?: string | null; acceptance_confirmed_at?: string | null }; referees?: Referee[]; priorDegrees?: PriorQual[]; documents?: DocMeta[]; history?: HistoryRow[]; screening?: Screening | null; screeningRequired?: boolean; student?: { admission_no: string; matric_no: string | null; status: string } | null }
const EVENT_LABEL: Record<string, string> = {
  CREATED: "Application opened", SUBMITTED: "Submitted", APPLICATION_FEE_CONFIRMED: "Application fee confirmed", REFERENCE_RECEIVED: "Reference received",
  DEPT_RECOMMENDED: "Department recommended", DEPT_DECLINED: "Department declined", FAC_RECOMMENDED: "Faculty recommended", FAC_DECLINED: "Faculty declined",
  OFFERED: "School offered", NOT_OFFERED: "School did not offer", CHECKING_FEE_CONFIRMED: "Checking fee confirmed", ACCEPTANCE_FEE_CONFIRMED: "Acceptance fee confirmed",
  ACCEPTED: "Offer accepted", ADMITTED: "Admitted to the register",
  RETURNED: "Returned to the applicant for correction", RESUBMITTED: "Resubmitted after correction", RETURNED_TO_DEPARTMENT: "Returned to the department by the School",
  SCREENING_PENDING: "Physical screening opened", SCREENING_SCHEDULED: "Physical screening scheduled", SCREENING_IN_PROGRESS: "Physical screening in progress",
  SCREENING_CLEARED: "Cleared at physical screening", SCREENING_NOT_CLEARED: "Not cleared at physical screening", SCREENING_CORRECTION_REQUIRED: "Correction required at screening",
};
const fmtWhen = (v: string) => new Date(v).toLocaleString("en-GB", { day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" });

/** the applications on the desk as a branded workbook: S/N first, names A–Z as the desk lists them */
async function exportRows(rows: PgRow[], session: string) {
  const headers = ["S/N", "Application number", "Applicant", "Programme", "Award", "Department", "Faculty", "Level", "Session", "Application fee", "Application status", "Submitted"];
  const body = rows.map((r, i) => [
    i + 1, r.application_no, `${r.surname}, ${r.other_names}`, r.programme_name, r.pg_award ?? "", r.department_name ?? "", r.faculty_name ?? "",
    r.entry_level, session, r.fee_confirmed_at ? "Paid" : "Unpaid", stageOf(r).label, r.submitted_at ? new Date(r.submitted_at).toLocaleDateString("en-GB") : "",
  ]);
  const blob = await brandedXlsx("Postgraduate applications", headers, body, { sheetName: "Applications", serial: docSerial("PGAPP"), sub: session });
  downloadBlob(blob, `postgraduate-applications-${session.replace("/", "-")}.xlsx`);
}
const QUAL_LABEL: Record<string, string> = {
  FIRST: "First degree", MASTERS: "Master’s degree", PGD: "Postgraduate Diploma", HND: "Higher National Diploma",
  ND: "National Diploma", NCE: "Nigeria Certificate in Education", PHD: "Doctorate (PhD)", OTHER: "Other qualification",
};

const STATE: Record<string, { kind: "ok" | "bad" | "warn" | "info" | "grey"; label: string }> = {
  DRAFT: { kind: "grey", label: "Draft" },
  SUBMITTED: { kind: "info", label: "Submitted" },
  RETURNED: { kind: "warn", label: "Returned for correction" },
  DEPT_RECOMMENDED: { kind: "info", label: "Dept recommended" },
  DEPT_DECLINED: { kind: "grey", label: "Dept declined" },
  FAC_RECOMMENDED: { kind: "info", label: "Faculty recommended" },
  FAC_DECLINED: { kind: "grey", label: "Faculty declined" },
  OFFERED: { kind: "ok", label: "Offered" },
  NOT_OFFERED: { kind: "grey", label: "Not offered" },
  ACCEPTED: { kind: "ok", label: "Accepted" },
  ADMITTED: { kind: "ok", label: "Admitted" },
};
const isDept = (o: string | null) => ["hod", "academic", "super"].includes(o ?? "");
const isFaculty = (o: string | null) => ["dean", "academic", "super"].includes(o ?? "");
const isSpgs = (o: string | null) => ["pgschool", "pgsecretary", "super"].includes(o ?? "");
const mayAdmit = (o: string | null) => ["pgschool", "pgsecretary", "registrar", "super"].includes(o ?? "");
/** V337: who screens accepted applicants — the School's officers and the Registry's screening offices, never a department */
const isScreener = (o: string | null) => ["pgschool", "pgsecretary", "academic", "registrar", "dregistrar", "super"].includes(o ?? "");
const stageOf = (r: PgRow) => {
  if (r.state === "ACCEPTED" && r.screening_state) return { kind: SCREENING[r.screening_state]?.kind ?? ("info" as const), label: `Accepted · ${(SCREENING[r.screening_state]?.label ?? r.screening_state).toLowerCase()}` };
  if (r.state === "SUBMITTED" && !r.fee_confirmed_at) return { kind: "grey" as const, label: "Submitted · fee unpaid" };
  return STATE[r.state] ?? { kind: "grey" as const, label: r.state };
};
const fmtDate = (v: string | null | undefined) => { if (!v) return "—"; const d = new Date(v); return Number.isNaN(d.getTime()) ? "—" : d.toLocaleDateString("en-GB", { day: "2-digit", month: "long", year: "numeric" }); };
const sexLabel = (v: string | null | undefined) => (v === "F" ? "Female" : v === "M" ? "Male" : "—");

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <div>
      <div className="eyebrow ink-chrome" style={{ borderBottom: "2px solid var(--line-2)", paddingBottom: 5, marginBottom: "var(--s-2)" }}>{title}</div>
      {children}
    </div>
  );
}
function Kv({ k, v }: { k: string; v: string }) {
  return (
    <div className="row row--base" style={{ gap: "var(--s-4)", padding: "6px 0", borderBottom: "1px solid var(--line-2)" }}>
      <span className="sub2" style={{ minWidth: 150, textTransform: "uppercase", letterSpacing: ".04em", fontSize: "var(--t-xs)" }}>{k}</span>
      <span className="b600" style={{ fontSize: "var(--t-base)" }}>{v}</span>
    </div>
  );
}

/** the applicant's physical screening on the application (V337): where it stands, and for a screening officer, the schedule and the decision */
function ScreeningBox({ id, screening, accepted, required, office, documents, busy, onAct }: {
  id: string; screening: Screening | null; accepted: boolean; required: boolean; office: string | null; documents: string[]; busy: boolean;
  onAct: (path: string, label: string, body?: unknown) => Promise<void>;
}) {
  const [venue, setVenue] = useState(screening?.venue ?? "");
  const [at, setAt] = useState("");
  const [decision, setDecision] = useState("CLEARED");
  const [verified, setVerified] = useState((screening?.verified_documents?.length ? screening.verified_documents : documents).join("\n"));
  const [missing, setMissing] = useState((screening?.missing_documents ?? []).join("\n"));
  const [issues, setIssues] = useState("");
  const [remarks, setRemarks] = useState("");
  const [reason, setReason] = useState("");
  const st = screening?.state ?? (required ? "PENDING" : null);
  const s = st ? SCREENING[st] : null;
  const may = isScreener(office) && accepted && st !== "CLEARED";
  const lines = (t: string) => t.split("\n").map((x) => x.trim()).filter(Boolean);
  void id;
  return (
    <Section title="Physical screening">
      <div className="row row--base" style={{ gap: "var(--s-3)", flexWrap: "wrap" }}>
        {s ? <Pil kind={s.kind}>{s.label}</Pil> : <Pil kind="grey">Not required for this session</Pil>}
        {screening?.scheduled_for ? <span className="sub2">{when(screening.scheduled_for)}{screening.venue ? ` · ${screening.venue}` : ""}</span> : null}
        {screening?.decided_at ? <span className="sub2">Decided {when(screening.decided_at)}{screening.officer ? ` by ${screening.officer}` : ""}</span> : null}
      </div>
      {screening?.reason ? <div className="sub2 mt-2"><b>Reason:</b> {screening.reason}</div> : null}
      {screening?.verified_documents?.length ? <div className="sub2 mt-1"><b>Verified:</b> {screening.verified_documents.join(" · ")}</div> : null}
      {screening?.missing_documents?.length ? <div className="sub2 mt-1"><b>Missing:</b> {screening.missing_documents.join(" · ")}</div> : null}
      {screening?.issues ? <div className="sub2 mt-1"><b>Issues:</b> {screening.issues}</div> : null}
      {screening?.remarks ? <div className="sub2 mt-1"><b>Remarks:</b> {screening.remarks}</div> : null}
      {may ? (
        <div className="stack mt-3">
          <div className="grid grid--3">
            <Field id={`scr-v-${id}`} label="Venue"><input id={`scr-v-${id}`} className="ctl" value={venue} maxLength={300} onChange={(e) => setVenue(e.target.value)} /></Field>
            <Field id={`scr-a-${id}`} label="Day and time"><input id={`scr-a-${id}`} type="datetime-local" className="ctl" value={at} onChange={(e) => setAt(e.target.value)} /></Field>
            <div style={{ alignSelf: "end" }}>
              <Btn kind="secondary" disabled={busy || !venue.trim() || !at} onClick={() => void onAct("screening/schedule", `Scheduled the physical screening for ${new Date(at).toLocaleString("en-GB")}`, { venue, at: new Date(at).toISOString() })}>{screening?.scheduled_for ? "Move the screening" : "Schedule the screening"}</Btn>
            </div>
          </div>
          <div className="grid grid--2">
            <Field id={`scr-ver-${id}`} label="Documents verified" hint="One per line"><textarea id={`scr-ver-${id}`} className="ctl" rows={4} value={verified} onChange={(e) => setVerified(e.target.value)} /></Field>
            <Field id={`scr-mis-${id}`} label="Documents missing" hint="One per line"><textarea id={`scr-mis-${id}`} className="ctl" rows={4} value={missing} onChange={(e) => setMissing(e.target.value)} /></Field>
            <Field id={`scr-iss-${id}`} label="Issues found"><textarea id={`scr-iss-${id}`} className="ctl" rows={2} value={issues} onChange={(e) => setIssues(e.target.value)} /></Field>
            <Field id={`scr-rem-${id}`} label="Officer's remarks" hint="For the file; not shown to the applicant"><textarea id={`scr-rem-${id}`} className="ctl" rows={2} value={remarks} onChange={(e) => setRemarks(e.target.value)} /></Field>
          </div>
          <div className="grid grid--2">
            <Field id={`scr-d-${id}`} label="Decision">
              <select id={`scr-d-${id}`} className="ctl" value={decision} onChange={(e) => setDecision(e.target.value)}>
                <option value="CLEARED">Cleared — admit to the register</option>
                <option value="CORRECTION_REQUIRED">Correction required</option>
                <option value="NOT_CLEARED">Not cleared</option>
                <option value="IN_PROGRESS">In progress</option>
              </select>
            </Field>
            <Field id={`scr-r-${id}`} label="Reason and next step" hint={decision === "NOT_CLEARED" || decision === "CORRECTION_REQUIRED" ? "Required: the applicant reads it" : "Optional"}>
              <textarea id={`scr-r-${id}`} className="ctl" rows={2} value={reason} onChange={(e) => setReason(e.target.value)} />
            </Field>
          </div>
          <div className="row">
            <Btn kind={decision === "CLEARED" ? "go" : decision === "NOT_CLEARED" ? "urgent" : "primary"}
              disabled={busy || ((decision === "NOT_CLEARED" || decision === "CORRECTION_REQUIRED") && !reason.trim())}
              onClick={() => void onAct("screening/decision", `Screening decision: ${decision.toLowerCase().replace(/_/g, " ")}`,
                { decision, verifiedDocuments: lines(verified), missingDocuments: lines(missing), issues, remarks, reason })}>
              Record the screening decision
            </Btn>
            {decision === "CLEARED" ? <span className="sub2">Clearing admits the applicant to the register at once; school fees open on the student portal.</span> : null}
          </div>
        </div>
      ) : null}
    </Section>
  );
}

function DetailPanel({ id, office, onChanged }: { id: string; office: string | null; onChanged: () => void }) {
  const [d, setD] = useState<Detail | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [note, setNote] = useState("");
  /* a document opened in a modal viewer on this page, rather than in a new tab */
  const [viewing, setViewing] = useState<{ url: string; title: string; image: boolean } | null>(null);

  useEffect(() => {
    let live = true;
    (async () => {
      try {
        const r = await fetch(`/api/bff/api/v1/pg/applications/${id}`);
        const j = (await r.json().catch(() => null)) as Detail | null;
        if (live) setD(j && j.found ? j : { found: false });
      } catch { if (live) setD({ found: false }); }
    })();
    return () => { live = false; };
  }, [id]);

  async function act(path: string, label: string, body?: unknown) {
    setBusy(path); setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/pg/applications/${id}/${path}`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(label) },
        body: JSON.stringify(body ?? {}),
      });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); notifyProblem(j && typeof j === "object" && "status" in j ? (j as Problem) : { status: r.status, title: r.statusText }); return; }
      notify(label);
      setD(j && (j as Detail).found ? (j as Detail) : d);
      onChanged();
    } finally { setBusy(null); }
  }

  if (!d) return <PBody><div className="sub2">Loading the application…</div></PBody>;
  if (!d.found || !d.application) return <PBody><div className="sub2">This application could not be read.</div></PBody>;
  const a = d.application;
  const st = a.state;
  const docUrl = (docId: string) => `/api/bff/api/v1/pg/applications/${id}/documents/${docId}`;
  const passport = (d.documents ?? []).find((x) => x.kind === "PASSPORT") ?? null;
  const otherDocs = (d.documents ?? []).filter((x) => x.kind !== "PASSPORT");
  const quals: PriorQual[] = (d.priorDegrees ?? []).length
    ? (d.priorDegrees ?? [])
    : [{ kind: "FIRST", institution: a.prior_institution, award: a.prior_award, field: null, class_of_degree: a.prior_class, cgpa: a.prior_cgpa, year: a.prior_year } as PriorQual];
  return (
    <PBody style={{ gap: "var(--s-5)" }}>
      {problem ? <ProblemNotice problem={problem} /> : null}

      {/* identity, with the passport shown as a photograph */}
      <div className="row row--top" style={{ gap: "var(--s-5)" }}>
        {passport ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={docUrl(passport.id)} alt="Passport photograph" style={{ width: 108, height: 132, objectFit: "cover", borderRadius: "var(--r-md)", border: "1px solid var(--line-2)" }} />
        ) : (
          <div className="sub2" style={{ width: 108, height: 132, borderRadius: "var(--r-md)", border: "1px dashed var(--line-2)", display: "grid", placeItems: "center", textAlign: "center", padding: "var(--s-2)" }}>No passport uploaded</div>
        )}
        <div style={{ minWidth: 0 }}>
          <div className="b700 t-lg">{a.surname}, {a.other_names}</div>
          <div className="sub2 mt-1">{a.application_no} · {a.programme_name}{a.pg_award ? ` (${a.pg_award})` : ""}</div>
          <div className="sub2">{a.email}{a.phone ? ` · ${a.phone}` : ""}</div>
        </div>
      </div>

      <Section title="Bio-data">
        <Kv k="Surname" v={a.surname} />
        <Kv k="Other names" v={a.other_names} />
        <Kv k="Sex" v={sexLabel(a.sex)} />
        <Kv k="Date of birth" v={fmtDate(a.date_of_birth)} />
        <Kv k="Nationality" v={a.nationality ?? "—"} />
        <Kv k="State of origin" v={a.state_of_origin ?? "—"} />
        <Kv k="LGA" v={a.lga ?? "—"} />
        <Kv k="Email" v={a.email} />
        <Kv k="Phone" v={a.phone ?? "—"} />
        <Kv k="Contact address" v={a.contact_address ?? "—"} />
      </Section>

      <Section title="Institutions attended">
        <div className="stack">
          {quals.map((q, i) => (
            <div key={i} style={{ border: "1px solid var(--line-2)", borderRadius: "var(--r-md)", padding: "var(--s-2) var(--s-3)" }}>
              <div className="b600" style={{ fontSize: "var(--t-base)" }}>
                {QUAL_LABEL[q.kind] ?? q.kind}{q.award ? ` — ${q.award}` : ""}{q.field ? ` (${q.field})` : ""}
              </div>
              <div className="sub2 mt-1">
                {[q.institution, q.class_of_degree, q.cgpa != null ? `CGPA ${q.cgpa}` : null, q.year != null ? String(q.year) : null].filter(Boolean).join(" · ") || "—"}
              </div>
            </div>
          ))}
        </div>
      </Section>

      {a.pg_research ? (
        <Section title="Research proposal">
          <div className="b600">{a.proposal_title || "—"}</div>
          {a.proposal_text ? <div className="sub2 mt-1" style={{ lineHeight: 1.5 }}>{a.proposal_text}</div> : null}
        </Section>
      ) : null}

      <Section title="Referees">
        {(d.referees ?? []).length ? (d.referees ?? []).map((r) => (
          <div key={r.id} className="mb-2" style={{ paddingBottom: "var(--s-2)", borderBottom: "1px solid var(--line-2)" }}>
            <div className="sub2"><b>{r.name}</b>{r.position ? ` · ${r.position}` : ""}{r.institution ? ` · ${r.institution}` : ""}</div>
            <div className="sub2">{r.email ? `${r.email}` : ""}{r.phone ? ` · ${r.phone}` : ""}</div>
            {r.submitted_at ? (
              <div className="mt-2" style={{ paddingLeft: "var(--s-2)", borderLeft: "3px solid var(--green-ink)" }}>
                <div className="sub2 ink-green b600">
                  Reference received{r.verdict ? ` · ${VERDICT_LABEL[r.verdict] ?? r.verdict}` : ""}
                </div>
                {r.relationship ? <div className="sub2"><b>Relationship:</b> {r.relationship}{r.known_duration ? ` · known ${r.known_duration}` : ""}</div> : null}
                {r.attestation ? <div className="sub2 mt-1" style={{ whiteSpace: "pre-wrap" }}><b>Attestation:</b> {r.attestation}</div> : null}
                {r.recommendation ? <div className="sub2 mt-1" style={{ whiteSpace: "pre-wrap" }}><b>Recommendation:</b> {r.recommendation}</div> : null}
              </div>
            ) : <div className="sub2 ink-chrome">Reference not yet submitted{r.email ? " — a request was emailed" : " (no email on record)"}.</div>}
          </div>
        )) : <div className="sub2">None named.</div>}
      </Section>

      <Section title="Documents">
        {otherDocs.length || passport ? (
          <div className="stack">
            <div className="row row--base">
              <span className="sub2">{(passport ? 1 : 0) + otherDocs.length} file{(passport ? 1 : 0) + otherDocs.length === 1 ? "" : "s"} uploaded{passport ? ", with the passport photograph" : ""}</span>
              <span className="grow" />
              <Btn kind="primary" onClick={() => setViewing({ url: `/api/bff/api/v1/pg/applications/${id}/documents.pdf`, title: "All documents — one PDF", image: false })}>View all as one PDF</Btn>
              <a href={`/api/bff/api/v1/pg/applications/${id}/documents.pdf`} download className="btn btn--ghost btn--sm">Download all</a>
            </div>
            <div className="tablewrap" style={{ border: "1px solid var(--line)", borderRadius: "var(--r-md)" }}>
              <table className="tbl tbl--data">
                <thead>
                  <tr><th style={{ width: 48 }}>S/N</th><th>Document</th><th>File name</th><th style={{ width: 170 }}>Uploaded</th><th style={{ width: 110 }} /></tr>
                </thead>
                <tbody>
                  {[...(passport ? [passport] : []), ...otherDocs].map((x, i) => {
                    const image = x.kind === "PASSPORT";
                    return (
                      <tr key={x.id}>
                        <td className="tnum">{i + 1}</td>
                        <td className="b600">{docLabel(x.kind)}</td>
                        <td className="sub2" style={{ wordBreak: "break-all" }}>{x.filename}</td>
                        <td className="sub2 tnum">{fmtWhen(x.uploaded_at)}</td>
                        <td style={{ textAlign: "right" }}>
                          <Btn kind="ghost" onClick={() => setViewing({ url: docUrl(x.id), title: `${docLabel(x.kind)} — ${x.filename}`, image })}>{image ? "View" : "View PDF"}</Btn>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </div>
        ) : <div className="sub2">No documents uploaded yet.</div>}
      </Section>

      {viewing ? (
        <Modal title={viewing.title} sub="Opens here; close to return to the application" wide onClose={() => setViewing(null)}
          foot={<><a href={viewing.url} download className="btn btn--ghost btn--sm">Download</a><span className="grow" /><Btn kind="primary" onClick={() => setViewing(null)}>Close</Btn></>}>
          {viewing.image ? (
            <div style={{ display: "flex", justifyContent: "center" }}>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={viewing.url} alt={viewing.title} style={{ maxWidth: "100%", maxHeight: "70vh", borderRadius: "var(--r-md)", border: "1px solid var(--line-2)" }} />
            </div>
          ) : (
            <iframe src={viewing.url} title={viewing.title} style={{ width: "100%", height: "72vh", border: "1px solid var(--line-2)", borderRadius: "var(--r-md)", background: "var(--surface)" }} />
          )}
        </Modal>
      ) : null}

      {a.dept_note ? <Note kind="info" title="Department note">{a.dept_note}</Note> : null}
      {a.fac_note ? <Note kind="info" title="Faculty note">{a.fac_note}</Note> : null}
      {a.spgs_note ? <Note kind="info" title="School note">{a.spgs_note}</Note> : null}

      {a.return_note && (st === "RETURNED" || (st === "SUBMITTED" && a.returned_to === "DEPARTMENT")) ? (
        <Note kind="info" title={st === "RETURNED" ? "Returned to the applicant for correction" : "Returned to the department by the School"}>
          {a.return_note}{a.returned_at ? <span className="sub2"> · {fmtWhen(a.returned_at)}</span> : null}
        </Note>
      ) : null}

      {(isDept(office) && st === "SUBMITTED" && a.fee_confirmed_at) || (isFaculty(office) && st === "DEPT_RECOMMENDED")
        || (isSpgs(office) && ["FAC_RECOMMENDED", "FAC_DECLINED", "DEPT_DECLINED", "DEPT_RECOMMENDED"].includes(st)) ? (
        <div>
          <textarea className="ctl" rows={2} value={note} onChange={(e) => setNote(e.target.value)} placeholder="A note for the decision — required to return the application, and read by the applicant when it is returned to them" />
        </div>
      ) : null}

      <div className="row">
        {isDept(office) && st === "SUBMITTED" && !a.fee_confirmed_at ? (
          <span className="sub2" style={{ alignSelf: "center" }}>The application fee is not yet confirmed: the department considers the application once it is.</span>
        ) : null}
        {isDept(office) && st === "SUBMITTED" && a.fee_confirmed_at ? (
          <>
            <Btn kind="primary" disabled={busy !== null} onClick={() => void act("dept-decision", `Department recommended ${a.surname}, ${a.other_names} for ${a.programme_name}`, { recommend: true, note })}>Department: recommend</Btn>
            <Btn kind="ghost" disabled={busy !== null} onClick={() => void act("dept-decision", `Department did not recommend ${a.surname}, ${a.other_names}`, { recommend: false, note })}>Not recommended</Btn>
            <Btn kind="secondary" disabled={busy !== null || !note.trim()} title={note.trim() ? undefined : "Write what the applicant must correct in the note first"}
              onClick={() => void act("return", `Returned ${a.surname}, ${a.other_names} to the applicant for correction`, { note })}>Return to applicant for correction</Btn>
          </>
        ) : null}
        {isFaculty(office) && st === "DEPT_RECOMMENDED" ? (
          <>
            <Btn kind="primary" disabled={busy !== null} onClick={() => void act("faculty-decision", `Faculty recommended ${a.surname}, ${a.other_names} for ${a.programme_name}`, { recommend: true, note })}>Faculty: recommend</Btn>
            <Btn kind="ghost" disabled={busy !== null} onClick={() => void act("faculty-decision", `Faculty declined ${a.surname}, ${a.other_names}`, { recommend: false, note })}>Decline</Btn>
          </>
        ) : null}
        {isSpgs(office) && ["FAC_RECOMMENDED", "FAC_DECLINED", "DEPT_DECLINED"].includes(st) ? (
          <>
            {st !== "FAC_RECOMMENDED" ? <span className="sub2" style={{ alignSelf: "center" }}>{st === "DEPT_DECLINED" ? "The department did not recommend." : "The faculty did not recommend."} The School&rsquo;s decision is final:</span> : null}
            <Btn kind="primary" disabled={busy !== null} onClick={() => void act("spgs-decision", `Offered ${a.surname}, ${a.other_names} a place on ${a.programme_name}`, { offer: true, note })}>Admit (offer a place)</Btn>
            <Btn kind="ghost" disabled={busy !== null} onClick={() => void act("spgs-decision", `Not admitted: ${a.surname}, ${a.other_names}`, { offer: false, note })}>Not admitted</Btn>
          </>
        ) : null}
        {isSpgs(office) && ["DEPT_RECOMMENDED", "DEPT_DECLINED", "FAC_RECOMMENDED", "FAC_DECLINED"].includes(st) ? (
          <Btn kind="secondary" disabled={busy !== null || !note.trim()} title={note.trim() ? undefined : "Write why it goes back in the note first"}
            onClick={() => void act("return-to-department", `Returned ${a.surname}, ${a.other_names} to the department`, { note })}>Return to the department</Btn>
        ) : null}
        {isSpgs(office) && st === "OFFERED" ? (
          <Btn kind="primary" disabled={busy !== null} onClick={() => void act("accept", `Recorded acceptance for ${a.surname}, ${a.other_names}`)}>Record acceptance</Btn>
        ) : null}
        {mayAdmit(office) && st === "ACCEPTED" && !d.screeningRequired ? (
          <Btn kind="primary" disabled={busy !== null} onClick={() => void act("admit", `Admitted ${a.surname}, ${a.other_names} onto the register`)}>Admit onto the register</Btn>
        ) : null}
        {st === "ACCEPTED" && d.screeningRequired ? <span className="sub2" style={{ alignSelf: "center" }}>Awaiting physical screening: clearance admits the applicant to the register.</span> : null}
        {st === "ADMITTED" ? <span className="sub2 ink-green" style={{ alignSelf: "center" }}>Admitted &mdash; on the register{d.student ? ` as ${d.student.matric_no ?? d.student.admission_no}` : ""}, {d.student?.matric_no ? "matriculated" : "awaiting school fees, registration and matriculation"}.</span> : null}
        {busy ? <span className="sub2" style={{ alignSelf: "center" }}>Working…</span> : null}
      </div>

      {st === "ACCEPTED" || d.screening ? (
        <ScreeningBox id={id} screening={d.screening ?? null} accepted={st === "ACCEPTED"} required={!!d.screeningRequired} office={office}
          documents={(d.documents ?? []).map((x) => docLabel(x.kind))} busy={busy !== null}
          onAct={(path, label, body) => act(path, label, body)} />
      ) : null}

      {d.history && d.history.length ? (
        <Section title="History">
          <ol className="plain" style={{ display: "grid", gap: 6 }}>
            {d.history.map((h, i) => (
              <li key={i} className="row row--base" style={{ gap: "var(--s-3)", flexWrap: "wrap" }}>
                <span className="tnum sub2" style={{ minWidth: 150 }}>{fmtWhen(h.at)}</span>
                <span className="b600">{EVENT_LABEL[h.kind] ?? h.kind.toLowerCase().replace(/_/g, " ")}</span>
                {h.note ? <span className="sub2">{h.note}</span> : null}
                {h.actor ? <span className="sub2">· {h.actor}{h.actor_office ? ` (${h.actor_office})` : ""}</span> : null}
              </li>
            ))}
          </ol>
        </Section>
      ) : null}
    </PBody>
  );
}

/** one postgraduate application on a page of its own: the applicant, the record, the documents, the screening, the decisions
 *  and the history, with the way back to the list of the session it was opened from */
export function PgApplicationPage({ id, session, actingOffice, heading }: {
  id: string; session: string | null; actingOffice: string | null;
  heading: { name: string; applicationNo: string; programme: string } | null;
}) {
  const router = useRouter();
  const back = `/admissions/postgraduate${session ? `?session=${encodeURIComponent(session)}` : ""}`;
  return (
    <>
      <PageHead eyebrow="Postgraduate admissions" title={heading ? heading.name : "Postgraduate application"}
        description={heading ? `${heading.applicationNo} · ${heading.programme}` : undefined}
        actions={<LinkBtn kind="secondary" href={back}>&larr; Back to applications</LinkBtn>} />
      <Panel title="Application" right={heading ? <span className="tnum sub2">{heading.applicationNo}</span> : null}>
        <DetailPanel id={id} office={actingOffice} onChanged={() => router.refresh()} />
      </Panel>
      <div className="row"><LinkBtn kind="ghost" href={back}>&larr; Back to applications</LinkBtn></div>
    </>
  );
}

export function PgAdmissions({ session, sessions = [], view, problem, actingOffice }: {
  session: string; sessions?: { name: string; state: string }[]; view: PgView | null; problem: Problem | null; actingOffice: string | null;
}) {
  const router = useRouter();
  const queryNav = useQueryNav();
  /** one application opens on a page of its own; the way back keeps the session */
  const detailHref = (id: string) => `/admissions/postgraduate/applications/${id}?session=${encodeURIComponent(session)}`;
  const [tab, setTab] = useState<"applications" | "screening">("applications");
  const c = view?.counts;
  const bound = actingOffice === "hod" || actingOffice === "dean";
  // the session on the desk is always among the options, even if the calendar doesn't list it yet
  const sessionOptions = sessions.some((s) => s.name === session) ? sessions : [{ name: session, state: "" }, ...sessions];
  return (
    <>
      <RoleLine allowed={["pgschool", "pgsecretary", "hod", "dean", "academic", "registrar"]} actingOffice={actingOffice}
        action="Deciding postgraduate admissions" />
      <Note kind="info" title="Postgraduate admission is decided on the record, not on a UTME score">
        A postgraduate applicant applies on a first degree — no JAMB, no UTME aggregate. The <b>department</b> considers its own applications once the fee is paid: it recommends, does not recommend, or returns one to the applicant for correction. The <b>faculty</b> vets a recommendation, and the <b>School of Postgraduate Studies</b> takes the final decision on every recommendation (or returns it to the department). The applicant checks their status, pays the acceptance fee, is screened in person where the session requires it, and is then on the register to pay school fees, register and be matriculated.
        {bound ? <> You see your own {actingOffice === "hod" ? "department" : "faculty"}&rsquo;s paid applications only.</> : null}
      </Note>

      <Panel title="Session" right={<span className="sub2">Applications are shown for the session you choose</span>}>
        <PBody>
          <div className="row">
            <label htmlFor="pg-session" className="sub2 b600">Admissions session</label>
            <select id="pg-session" className="ctl" style={{ maxWidth: 260 }} value={session}
              onChange={(e) => queryNav(`/admissions/postgraduate?session=${encodeURIComponent(e.target.value)}`)}>
              {sessionOptions.map((s) => (
                <option key={s.name} value={s.name}>{s.name}{s.state === "CURRENT" ? " · current" : s.state === "PLANNED" ? " · planned" : ""}</option>
              ))}
            </select>
          </div>
        </PBody>
      </Panel>

      {problem ? <ProblemNotice problem={problem} /> : null}

      {view ? (
        <>
          <Tiles items={[
            ["Applications", String(c?.total ?? 0), null, bound ? `${session} · paid` : session],
            ["Submitted", String(c?.submitted ?? 0), Number(c?.submitted) ? "var(--chrome)" : null, "Awaiting the department"],
            ["Returned", String(c?.returned ?? 0), Number(c?.returned) ? "var(--chrome)" : null, "With the applicant to correct"],
            ["Dept recommended", String(c?.recommended ?? 0), Number(c?.recommended) ? "var(--chrome)" : null, "Awaiting the faculty"],
            ["Faculty recommended", String(c?.faculty ?? 0), Number(c?.faculty) ? "var(--chrome)" : null, "Awaiting the School"],
            ["Not recommended", String(c?.not_recommended ?? 0), Number(c?.not_recommended) ? "var(--chrome)" : null, "Awaiting the School's final word"],
            ["Offered", String(c?.offered ?? 0), Number(c?.offered) ? "var(--green-ink)" : null, "Awaiting acceptance"],
            ["Admitted", String(c?.admitted ?? 0), Number(c?.admitted) ? "var(--green-ink)" : null, "On the register"],
          ]} cls="grid--4" />

          {isScreener(actingOffice) ? (
            <div className="row row--inline" role="tablist" aria-label="Postgraduate admissions desk">
              <Btn kind={tab === "applications" ? "primary" : "ghost"} size="sm" onClick={() => setTab("applications")}>Applications</Btn>
              <Btn kind={tab === "screening" ? "primary" : "ghost"} size="sm" onClick={() => setTab("screening")}>Physical screening</Btn>
            </div>
          ) : null}

          {tab === "screening" && isScreener(actingOffice) ? (
            <ScreeningDesk session={session} mayWritePolicy={isSpgs(actingOffice)} onOpen={(id) => router.push(detailHref(id))} />
          ) : null}

          {tab === "applications" ? <Panel title="Postgraduate applications" right={<span className="row row--inline row--tight">
            <span className="sub2">{view.rows.length} application{view.rows.length === 1 ? "" : "s"} · name A–Z</span>
            {view.rows.length ? <Btn kind="ghost" onClick={() => void exportRows(view.rows, session)}>Download Excel</Btn> : null}
          </span>}>
            {view.rows.length ? (
              <DTable
                cols={["S/N|num", "Applicant", "Programme", "Level|mid", "First degree", "Stage|mid", "|num"]}
                rows={view.rows.map((r, i) => {
                  const st = stageOf(r);
                  return [
                    <span key="sn" className="tnum sub2">{i + 1}</span>,
                    <Two key="n" a={`${r.surname}, ${r.other_names}`} b={r.application_no} />,
                    <span key="p"><span>{r.programme_name}</span><div className="sub2">{r.pg_award ?? ""}{r.pg_research ? " · research" : ""}</div></span>,
                    <span className="tnum" key="l">{r.entry_level}</span>,
                    <span className="sub2" key="d">{r.prior_award ?? "—"}{r.prior_class ? ` · ${r.prior_class}` : ""}</span>,
                    <Pil kind={st.kind} key="s">{st.label}</Pil>,
                    <LinkBtn kind="ghost" key="a" href={detailHref(r.id)}>Details</LinkBtn>,
                  ];
                })}
                texts={view.rows.map((r) => `${r.surname} ${r.other_names} ${r.application_no} ${r.programme_name} ${r.state}`)}
              />
            ) : <PBody><div className="sub2">No postgraduate application has been submitted for {session} yet.</div></PBody>}
          </Panel> : null}
        </>
      ) : (
        <Note kind="bad" title="The postgraduate applications could not be read">The desk reads the postgraduate admissions register; it did not answer.</Note>
      )}
    </>
  );
}
