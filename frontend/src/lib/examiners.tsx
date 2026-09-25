/** External examiners (V254): the shapes the API returns and the small pieces the screens share. */
import { Pil } from "@/components/proto/ui";

export interface ExaminerRow {
  id: string; person_id: string; title: string | null; surname: string; given_names: string; name: string; email: string; phone: string | null; institution: string; department: string | null;
  rank: string | null; specialization: string | null; qualification: string | null; professional: string | null; experience_years: number | null; country: string | null; region: string | null;
  orcid: string | null; status: string; notes?: string | null; created_at: string; activated_at: string | null; pg_examiner_id: string | null;
  assigned: number; pending: number; submitted: number; overdue: number; live_appointments: number; last_invited_at: string | null; invitation_expires_at: string | null; has_signin: boolean; last_sign_in_at: string | null;
}
export interface Appointment { id: string; examiner_id?: string; examiner?: string; institution?: string; examiner_status?: string; session: string; semester: number | null; faculty_code: string; faculty: string; dept_code: string; department: string; programme_code: string | null; programme: string | null; period: string | null; starts_on: string; ends_on: string; status: string; instrument: string | null; appointed_at: string; appointed_by?: string | null; assignments?: number }
export interface ProjectRow {
  id: string; kind: "UNDERGRADUATE" | "POSTGRADUATE"; session: string; title: string; abstract: string | null; keywords: string | null; project_type: string | null; submitted_on: string | null;
  supervisor_id: string | null; supervisor: string | null; co_supervisor: string | null; pg_research_id: string | null; course_code: string | null; created_at: string;
  student_id: string; student: string; number: string; level: number; programme_code: string; programme: string; dept_code: string; department: string; faculty_code: string; faculty: string;
  documents: number; examiners: number; examiner_names: string | null; submitted: number;
}
export interface Doc { id: string; kind: string; filename: string; content_type: string; bytes: number; released?: boolean; uploaded_at: string }
export interface AssignmentRow {
  id: string; project_id: string; examiner_id: string; examiner: string; institution: string; examiner_status: string; appointment_id: string | null; rubric_id: string; rubric: string;
  deadline: string; exam_date: string | null; status: string; assigned_at: string; first_viewed_at: string | null; ended_at: string | null; ended_reason: string | null; replaced_by: string | null; assigned_by: string | null;
  overdue: boolean; days_left: number; title: string; kind: string; session: string; student: string; number: string; programme: string; department: string; dept_code: string; faculty: string; supervisor: string | null; submitted_on: string | null;
  assessment_id: string | null; assessment_state: string | null; total: number | null; max_total: number | null; percentage: number | null; grade: string | null; final_recommendation: string | null; submitted_at: string | null; locked_at: string | null; reopened_at: string | null;
}
export interface Line { criterion_id: string; section: "WRITTEN" | "DEFENCE"; name: string; guidance: string | null; max_score: number; ordinal: number; score: number | null; comment: string | null }
export interface Assessment {
  id: string; state: "DRAFT" | "SUBMITTED" | "LOCKED" | "REOPENED"; total: number | null; max_total: number | null; percentage: number | null; grade: string | null;
  general_comments: string | null; strengths: string | null; weaknesses: string | null; recommendations: string | null; corrections: string | null; final_recommendation: string | null;
  version: number; started_at: string; saved_at: string; submitted_at: string | null; locked_at: string | null; reopened_at: string | null; reopen_reason: string | null;
}
export interface Event { at: string; actor_name?: string; actor_office?: string | null; action: string; from_value: string | null; to_value: string | null; reason: string | null }
export interface Criterion { id: string; section: string; name: string; guidance: string | null; max_score: number; ordinal: number; active: boolean }
export interface Rubric { id: string; code: string; name: string; kind: string; active: boolean; has_defence: boolean; note: string | null; used: number; criteria: Criterion[] }
export interface MyAssignment {
  id: string; project_id: string; deadline: string; exam_date: string | null; status: string; assigned_at: string; first_viewed_at: string | null; overdue: boolean; days_left: number;
  title: string; kind: string; session: string; submitted_on: string | null; project_type: string | null; student: string; number: string; programme: string; department: string; faculty: string; supervisor: string | null; co_supervisor: string | null;
  documents: number; assessment_id: string | null; assessment_state: string | null; total: number | null; max_total: number | null; percentage: number | null; grade: string | null; final_recommendation: string | null; submitted_at: string | null; saved_at: string | null;
}

export const STATUS: Record<string, [string, "grey" | "info" | "ok" | "bad" | "warn"]> = {
  ASSIGNED: ["Not started", "info"], IN_REVIEW: ["In review", "warn"], SUBMITTED: ["Submitted", "ok"], LOCKED: ["Locked", "ok"], REOPENED: ["Reopened", "bad"], REASSIGNED: ["Reassigned", "grey"], WITHDRAWN: ["Withdrawn", "grey"],
};
export const EXAMINER_STATUS: Record<string, [string, "grey" | "info" | "ok" | "bad" | "warn"]> = {
  INVITED: ["Invited", "grey"], PENDING_ACTIVATION: ["Pending activation", "info"], ACTIVE: ["Active", "ok"], SUSPENDED: ["Suspended", "bad"], INACTIVE: ["Inactive", "grey"],
};
export const RECOMMENDATION: Record<string, [string, "grey" | "info" | "ok" | "bad" | "warn"]> = {
  PASS: ["Pass", "ok"], PASS_WITH_CORRECTIONS: ["Pass subject to corrections", "info"], REASSESSMENT: ["Reassessment required", "warn"], FAIL: ["Fail", "bad"],
};
export const ACTION: Record<string, string> = {
  EXAMINER_CREATED: "Examiner created", EXAMINER_EDITED: "Record edited", EXAMINER_INVITED: "Invitation sent", INVITATION_RESENT: "Invitation resent", ACCOUNT_ACTIVATED: "Account activated", EXAMINER_STATUS: "Status changed",
  APPOINTED: "Appointed", APPOINTMENT_ENDED: "Appointment ended", PROJECT_CREATED: "Project registered", PROJECT_EDITED: "Project edited", DOCUMENT_RELEASED: "Document released", DOCUMENT_WITHDRAWN: "Document withdrawn",
  PROJECT_ASSIGNED: "Project assigned", PROJECT_REASSIGNED: "Project reassigned", ASSIGNMENT_WITHDRAWN: "Assignment withdrawn", DEADLINE_CHANGED: "Deadline changed", PROJECT_VIEWED: "Project viewed by the examiner",
  ASSESSMENT_STARTED: "Assessment started", ASSESSMENT_SAVED: "Draft saved", ASSESSMENT_SUBMITTED: "Assessment submitted", ASSESSMENT_LOCKED: "Assessment locked", ASSESSMENT_REOPENED: "Assessment reopened", ASSESSMENT_RESUBMITTED: "Assessment resubmitted",
};
export const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");
export const dayOf = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—");
export const human = (bytes: number) => (bytes < 1024 ? `${bytes} B` : bytes < 1048576 ? `${Math.round(bytes / 1024)} KB` : `${(bytes / 1048576).toFixed(1)} MB`);
export const daysWords = (days: number | null | undefined, status: string) =>
  ["SUBMITTED", "LOCKED", "REASSIGNED", "WITHDRAWN"].includes(status) || days == null ? "—" : days < 0 ? `Overdue by ${-days} day${days === -1 ? "" : "s"}` : days === 0 ? "Due today" : `${days} day${days === 1 ? "" : "s"} left`;
export const DOC_KIND: Record<string, string> = { PROPOSAL: "Project proposal", REPORT: "Final project report", SOURCE: "Source code", PRESENTATION: "Presentation", SUPPORTING: "Supporting document" };
export const docType = (t: string) => (t === "application/pdf" ? "PDF" : t.includes("wordprocessingml") ? "Word" : t.includes("presentationml") ? "PowerPoint" : t === "application/zip" ? "ZIP" : t);
export const DOC_MIME = ["application/pdf", "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "application/vnd.openxmlformats-officedocument.presentationml.presentation", "application/zip"];
export const DOC_MAX = 25 * 1024 * 1024;

export function readBase64(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(String(r.result).split(",")[1] ?? "");
    r.onerror = () => reject(new Error("could not read the file"));
    r.readAsDataURL(file);
  });
}
/** a browser sometimes reports a ZIP as application/x-zip-compressed, or nothing at all: the extension decides */
export function mimeOf(file: File): string {
  const n = file.name.toLowerCase();
  if (n.endsWith(".pdf")) return "application/pdf";
  if (n.endsWith(".docx")) return "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
  if (n.endsWith(".pptx")) return "application/vnd.openxmlformats-officedocument.presentationml.presentation";
  if (n.endsWith(".zip")) return "application/zip";
  return file.type;
}

export function StatusPil({ status }: { status: string }) {
  const s = STATUS[status] ?? [status, "grey"];
  return <Pil kind={s[1]}>{s[0]}</Pil>;
}
export function ExaminerPil({ status }: { status: string }) {
  const s = EXAMINER_STATUS[status] ?? [status, "grey"];
  return <Pil kind={s[1]}>{s[0]}</Pil>;
}
export function RecommendationPil({ value }: { value: string | null | undefined }) {
  if (!value) return <span className="sub2">—</span>;
  const s = RECOMMENDATION[value] ?? [value, "grey"];
  return <Pil kind={s[1]}>{s[0]}</Pil>;
}

/** the history as the shared timeline */
export function History({ events }: { events: Event[] }) {
  if (!events.length) return <div className="sub2">Nothing recorded yet.</div>;
  return (
    <ol className="hist">
      {events.map((e, i) => {
        const kind = e.action.includes("SUBMITTED") || e.action === "ASSESSMENT_LOCKED" || e.action === "ACCOUNT_ACTIVATED" ? "ok" : e.action.includes("REOPENED") || e.action.includes("WITHDRAWN") ? "bad" : "step";
        const change = [e.from_value, e.to_value].filter(Boolean).map((v) => STATUS[v!]?.[0] ?? EXAMINER_STATUS[v!]?.[0] ?? v).join(" → ");
        return (
          <li key={i} className={`hist__it hist__it--${kind}`}>
            <span className="hist__mark" aria-hidden="true" />
            <div className="hist__body">
              <div className="row row--base row--tight"><strong>{ACTION[e.action] ?? e.action}</strong>{change ? <span className="sub2">{change}</span> : null}</div>
              {e.reason ? <div className="hist__detail">{e.reason}</div> : null}
              <div className="sub2 tnum">{e.actor_name ?? "The portal"}{e.actor_office ? ` · ${e.actor_office}` : ""} · {when(e.at)}</div>
            </div>
          </li>
        );
      })}
    </ol>
  );
}

/** the released documents, opened through the endpoint that checks who is asking */
export function Documents({ items, href, extra }: { items: Doc[]; href: (d: Doc) => string; extra?: (d: Doc) => React.ReactNode }) {
  if (!items.length) return <div className="sub2">No documents released yet.</div>;
  return (
    <ul className="plain stack">
      {items.map((d) => (
        <li key={d.id} className="row row--base">
          <a className="lnk b600" href={href(d)} target="_blank" rel="noreferrer">{d.filename}</a>
          <span className="sub2">{DOC_KIND[d.kind] ?? d.kind} · {docType(d.content_type)} · {human(Number(d.bytes))} · {dayOf(d.uploaded_at)}</span>
          {d.released === false ? <Pil kind="grey">Withheld</Pil> : null}
          {extra ? extra(d) : null}
        </li>
      ))}
    </ul>
  );
}
