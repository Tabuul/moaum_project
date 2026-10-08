/** ICT support tickets (V251): the shapes the API returns, and the small pieces every ticket screen shares —
 *  the status and priority pills, the history as a timeline, the attachments list, the category's fields. */
import type { ReactNode } from "react";
import { KvGrid, Pil } from "@/components/proto/ui";

export interface TicketRow {
  id: string; number: string; subject: string; status: string; priority: string; created_at: string; updated_at: string;
  resolved_at: string | null; closed_at: string | null; reopen_count: number;
  category_code: string; category: string; requester_kind: "STUDENT" | "STAFF" | "JUPEB" | "PUBLIC"; requester_name: string; requester_number: string | null; requester_email: string | null;
  department_code: string | null; department: string | null; faculty_code: string | null; faculty: string | null;
  assigned_to: string | null; agent: string | null; escalated: boolean; due_at: string | null; overdue: boolean; response_overdue: boolean; attachments: number;
  /** V328: the support queue the ticket is worked in, and the University office it waits on, if any */
  queue_code: string | null; queue: string | null; escalated_office: string | null; office: string | null; waiting_since: string | null;
}
/** who raised a ticket, in a word; V363's PUBLIC asked from the sign-in page while not signed in, and nothing it says is proven */
export function requesterKind(kind: string): string {
  return kind === "STUDENT" ? "Student" : kind === "JUPEB" ? "JUPEB candidate" : kind === "PUBLIC" ? "Not signed in" : "Staff";
}
/** what the requester's number is: the record's own, or (V363) only what the person typed */
export function requesterNumberLabel(kind: string): string {
  return kind === "STUDENT" ? "Matriculation number" : kind === "JUPEB" ? "JUPEB application number" : kind === "PUBLIC" ? "Number given (unconfirmed)" : "Staff number";
}
export interface Comment { id: string; author_kind: "REQUESTER" | "AGENT" | "SYSTEM"; author_name: string; internal: boolean; body: string; created_at: string }
export interface Attachment { id: string; comment_id: string | null; uploaded_kind: string; uploader_name: string; filename: string; content_type: string; bytes: number; internal: boolean; uploaded_at: string }
export interface Event { id?: string; at: string; actor_kind?: string; actor_name?: string; actor?: string; action: string; from_value: string | null; to_value: string | null; detail: string | null; internal?: boolean }
export interface Ticket extends Omit<TicketRow, "attachments"> {
  description: string; details: string; fields: string; attachment_hint: string | null; requester_phone: string | null;
  /** V334: the student (or staff) record behind the requester, for the support desk's student screen */
  requester_id?: string | null;
  assigned_by_name: string | null; assigned_at: string | null;
  escalated_to_name: string | null; escalated_by_name: string | null; escalated_at: string | null; escalation_reason: string | null;
  opened_at: string | null; opened_by_name: string | null; first_response_at: string | null; in_progress_at: string | null; response_due_at: string | null;
  resolved_by_name: string | null; resolution_summary: string | null; resolution_details: string | null;
  closed_by_kind: string | null; closed_by_name: string | null; closure_reason: string | null;
  comments: Comment[]; attachments: Attachment[]; timeline: Event[];
  /** V328, the desk's view only: where the ticket may be escalated — the queue's office for a decision, the Director of ICT for a fault */
  escalation_offices?: { code: string; label: string; technical: boolean }[];
}
export interface Field { key: string; label: string; type: "text" | "date" | "number" | "select" | "session" | "semester" | "level"; required?: boolean; options?: string[]; hint?: string }
export interface Category { id: string; code: string; name: string; description: string | null; suggested_priority: string; fields: string; attachment_hint: string | null; active?: boolean; ordinal?: number; tickets?: number }
export interface Profile { kind: "STUDENT" | "STAFF"; name: string; number: string | null; email: string | null; phone: string | null; department: string | null; departmentCode: string | null; faculty: string | null; facultyCode: string | null; programme: string | null; openTickets: number }
export interface Agent {
  id: string; name: string; staff_number: string | null; reachable: boolean; offices: string; director: boolean; open: number;
  /** V328: the Head or the Director; the queues and scopes the person is posted on; and, against a ticket, whether the routing would choose them */
  head?: boolean; queues?: string | null; scopes?: string | null; availability?: string | null; eligible?: boolean; posted?: boolean;
}
/** V328: a support queue with its load, as /api/v1/helpdesk/queues gives it */
export interface Queue {
  code: string; name: string; office_code: string | null; office: string | null; active: boolean; agents: number; available_agents: number;
  open: number; unassigned: number; in_progress: number; waiting_student: number; waiting_office: number; overdue: number; critical: number; resolved_week: number;
  description?: string | null; ordinal?: number; supervisor?: string | null;
}
/** V328: an agent's posting on a queue within a scope */
export interface Posting {
  id: string; person_id: string; name: string; staff_number: string | null; email: string | null; left_the_university: boolean; holds_office: boolean;
  queue_code: string; queue: string; scope_kind: string; scope_ref: string | null; scope_name: string; is_primary: boolean; active: boolean; availability: string;
  effective_from: string; effective_to: string | null; assigned_by: string | null; reason: string | null; created_at: string; updated_at: string; open: number;
  /** V334: the student-record capabilities the Head granted with the posting, comma-separated */
  capabilities?: string | null;
}
export interface RoutingRule {
  id: string; category_code: string; category: string; faculty_code: string | null; faculty: string | null; department_code: string | null; department: string | null;
  queue_code: string; queue: string; strategy: string; priority_floor: string | null; active: boolean; created_at: string;
}
export interface Workload {
  person_id: string; name: string; staff_number: string | null; queues: string | null; availability: string; scopes: string | null;
  open: number; in_progress: number; waiting: number; overdue: number; critical: number; resolved_today: number; resolved_week: number; avg_resolution_hours: number | null;
}
/** the offices that see every ticket and run the desk: the Head of ICT Support Desk, the Director of ICT, the administrators (V328) */
export const HEADS = ["helpdeskhead", "ict", "admin", "super"];
export const SCOPE_KINDS: Record<string, string> = { GLOBAL: "The University", FACULTY: "A faculty", COLLEGE: "A college", DEPARTMENT: "A department", OFFICE: "An office" };
export const AVAILABILITY: Record<string, [string, "grey" | "info" | "ok" | "bad" | "warn"]> = {
  AVAILABLE: ["Available", "ok"], BUSY: ["Busy", "warn"], AWAY: ["Away", "grey"], OFFLINE: ["Offline", "grey"], ON_LEAVE: ["On leave", "bad"],
};
export const STRATEGY: Record<string, [string, string]> = {
  FACULTY_AGENT_FIRST: ["Faculty agent first", "An agent posted to the ticket's faculty, college or department before a University-wide one; then the least loaded"],
  OFFICE_AGENT_FIRST: ["Office agent first", "An agent posted to an office before any other; then the least loaded"],
  LEAST_LOADED: ["Least loaded", "The eligible agent with the fewest open tickets"],
  ROUND_ROBIN: ["Round robin", "The eligible agent assigned longest ago"],
  MANUAL: ["Manual", "Queued for the Head of ICT Support Desk to assign"],
  QUEUE_ONLY: ["Queue only", "Left on the queue for its agents to take"],
};

export const STATUS: Record<string, [string, "grey" | "info" | "ok" | "bad" | "warn"]> = {
  SUBMITTED: ["Submitted", "info"], OPENED: ["Opened", "info"], IN_PROGRESS: ["In progress", "warn"], WAITING_FOR_STUDENT: ["Waiting for requester", "warn"], WAITING_FOR_OFFICE: ["With an office", "warn"],
  RESOLVED: ["Resolved", "ok"], CLOSED: ["Closed", "grey"], REOPENED: ["Reopened", "bad"],
};
export const PRIORITY: Record<string, [string, "grey" | "info" | "ok" | "bad" | "warn"]> = {
  LOW: ["Low", "grey"], NORMAL: ["Normal", "info"], HIGH: ["High", "warn"], URGENT: ["Urgent", "bad"], CRITICAL: ["Critical", "bad"],
};
export const ACTION: Record<string, string> = {
  SUBMITTED: "Ticket submitted", OPENED: "Ticket opened", STATUS_CHANGED: "Status changed", ASSIGNED: "Assigned", REASSIGNED: "Reassigned", ESCALATED: "Escalated",
  PRIORITY_CHANGED: "Priority changed", INTERNAL_NOTE: "Internal note", UPDATE: "Update", RESOLUTION: "Resolution added", REOPENED: "Reopened", CLOSED: "Closed", ATTACHMENT: "Attachment added",
  ROUTED: "Routed to a queue", QUEUED: "Queued, no agent", TRANSFERRED: "Transferred", WAITING: "Waiting on the requester", ESCALATED_TO_OFFICE: "Escalated to an office", OFFICE_ANSWERED: "The office answered", RETURNED: "Returned to the queue",
  // V334/V346: the support acts done on the student's record for the ticket
  SUPPORT_CONTACT_EDITED: "Support: contact corrected", SUPPORT_PERSONAL_EDITED: "Support: personal detail corrected", SUPPORT_FAMILY_EDITED: "Support: family detail corrected",
  SUPPORT_PHOTO_REPLACED: "Support: photograph replaced", SUPPORT_CHANGE_REQUESTED: "Support: change requested of the Registry", SUPPORT_REGISTRATION_CHOSEN: "Support: courses chosen",
  SUPPORT_COURSE_ADDED: "Support: course added", SUPPORT_COURSE_DROPPED: "Support: course dropped", SUPPORT_COURSE_RESTORED: "Support: course restored",
  SUPPORT_REGISTRATION_SUBMITTED: "Support: registration submitted", SUPPORT_PASSWORD_RESET: "Support: password reset initiated", SUPPORT_PAYMENT_INVESTIGATED: "Support: payment investigated",
  SUPPORT_PAYMENT_VERIFIED: "Support: payment verified", SUPPORT_ENTITLEMENT_REFRESHED: "Support: payment entitlement synchronized", SUPPORT_RECEIPT_REGENERATED: "Support: receipt regenerated",
  SUPPORT_ESCALATED: "Support: escalated", SUPPORT_TICKET_CREATED: "Support: ticket raised at the desk", SUPPORT_TICKET_RESOLVED: "Support: ticket resolved",
};
export const statusWord = (s: string) => STATUS[s]?.[0] ?? s;
export const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");
export const dayOf = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—");
export const human = (bytes: number) => (bytes < 1024 ? `${bytes} B` : bytes < 1048576 ? `${Math.round(bytes / 1024)} KB` : `${(bytes / 1048576).toFixed(1)} MB`);
export const parse = <T,>(s: string | null | undefined, fallback: T): T => { try { return s ? (JSON.parse(s) as T) : fallback; } catch { return fallback; } };
/** a due time in words: "due in 3 h", "overdue by 2 d", "due today" */
export function dueWords(iso: string | null | undefined, settled: boolean): string {
  if (!iso || settled) return "—";
  const ms = new Date(iso).getTime() - Date.now();
  const abs = Math.abs(ms);
  const span = abs < 3600e3 ? `${Math.max(1, Math.round(abs / 60e3))} min` : abs < 48 * 3600e3 ? `${Math.round(abs / 3600e3)} h` : `${Math.round(abs / 86400e3)} d`;
  return ms < 0 ? `Overdue by ${span}` : `Due in ${span}`;
}
export interface Activity { id: string; at: string; actor_kind: string; actor_name: string; action: string; from_value: string | null; to_value: string | null; detail: string | null; internal: boolean; ticket_id: string; number: string; subject: string; status: string; priority: string; queue_code?: string | null }
/** what needs attention now, within the reader's scope, and the reader's own share — from /api/v1/helpdesk/counts */
export interface Counts {
  open: number; new: number; unassigned: number; urgent: number; critical: number; escalated: number; overdue: number; waiting: number;
  mine: number; mine_new: number; mine_in_progress: number; mine_waiting: number; mine_escalated: number; mine_overdue: number;
  latest_new: string | null; at: string; head: boolean;
  /** V346: the open tickets of the kinds the support desk resolves from the student's record */
  registration_issues?: number; payment_issues?: number; password_issues?: number;
}
/** a moment in words relative to now: "just now", "3 min ago", "2 h ago", "4 d ago" */
export function ago(iso: string | null | undefined): string {
  if (!iso) return "—";
  const ms = Date.now() - new Date(iso).getTime();
  if (ms < 60e3) return "just now";
  if (ms < 3600e3) return `${Math.round(ms / 60e3)} min ago`;
  if (ms < 48 * 3600e3) return `${Math.round(ms / 3600e3)} h ago`;
  return `${Math.round(ms / 86400e3)} d ago`;
}
export const EMAIL_OK = /^[^\s@]+@[^\s@]+\.[A-Za-z]{2,}$/;
export const hours = (h: number | null | undefined) => (h == null ? "—" : Number(h) < 48 ? `${Number(h).toFixed(1)} h` : `${(Number(h) / 24).toFixed(1)} d`);

/** read a file as base64 without the data-URI prefix, for the JSON upload the API takes */
export function readBase64(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(String(r.result).split(",")[1] ?? "");
    r.onerror = () => reject(new Error("could not read the file"));
    r.readAsDataURL(file);
  });
}
export const FILE_TYPES = ["application/pdf", "image/jpeg", "image/png"];
export const MAX_FILE = 5 * 1024 * 1024;

export function StatusPil({ status }: { status: string }) {
  const s = STATUS[status] ?? [status, "grey"];
  return <Pil kind={s[1]}>{s[0]}</Pil>;
}
export function PriorityPil({ priority }: { priority: string }) {
  const p = PRIORITY[priority] ?? [priority, "grey"];
  return <Pil kind={p[1]}>{p[0]}</Pil>;
}

/** the ticket's history as a timeline: a mark, what happened, who, when */
const DESK_ONLY = new Set(["INTERNAL_NOTE", "ESCALATED", "PRIORITY_CHANGED", "ROUTED", "QUEUED", "RETURNED", "ESCALATED_TO_OFFICE", "OFFICE_ANSWERED"]);
const DESK_DETAIL = new Set(["ASSIGNED", "REASSIGNED", "TRANSFERRED"]);
const ARROWED = new Set(["ASSIGNED", "REASSIGNED", "ESCALATED", "ROUTED", "QUEUED", "TRANSFERRED", "ESCALATED_TO_OFFICE", "OFFICE_ANSWERED", "RETURNED"]);

export function Timeline({ events, showInternal = true }: { events: Event[]; showInternal?: boolean }) {
  // the requester's and the public view never carry the desk's own business, whatever the data holds
  const rows = (events ?? []).filter((e) => showInternal || (!e.internal && !DESK_ONLY.has(e.action))).map((e) => (showInternal || !DESK_DETAIL.has(e.action) ? e : { ...e, detail: null }));
  if (!rows.length) return <div className="sub2">Nothing recorded yet.</div>;
  return (
    <ol className="hist">
      {rows.map((e, i) => {
        const kind = e.action === "CLOSED" ? "done" : e.action === "REOPENED" ? "bad" : e.action === "RESOLUTION" ? "ok" : e.internal ? "note" : "step";
        const title = ACTION[e.action] ?? e.action;
        const change = e.action === "STATUS_CHANGED" || e.action === "OPENED" || e.action === "REOPENED" || e.action === "CLOSED" || e.action === "RESOLUTION"
          ? [e.from_value, e.to_value].filter(Boolean).map((v) => statusWord(v!)).join(" → ")
          : e.action === "WAITING" ? statusWord("WAITING_FOR_STUDENT")
          : ARROWED.has(e.action) ? [e.from_value, e.to_value].filter(Boolean).join(" → ")
          : e.action === "PRIORITY_CHANGED" ? [e.from_value, e.to_value].filter(Boolean).map((v) => PRIORITY[v!]?.[0] ?? v).join(" → ") : "";
        return (
          <li key={e.id ?? i} className={`hist__it hist__it--${kind}`}>
            <span className="hist__mark" aria-hidden="true" />
            <div className="hist__body">
              <div className="row row--base row--tight"><strong>{title}</strong>{change ? <span className="sub2">{change}</span> : null}{e.internal ? <Pil kind="grey">Internal</Pil> : null}</div>
              {e.detail ? <div className="hist__detail">{e.detail}</div> : null}
              <div className="sub2 tnum">{e.actor_name ?? e.actor ?? "—"} · {when(e.at)}</div>
            </div>
          </li>
        );
      })}
    </ol>
  );
}

/** the files on the ticket, each opened through the endpoint that checks who is asking */
export function Attachments({ items, href }: { items: Attachment[]; href: (a: Attachment) => string }) {
  if (!items.length) return <div className="sub2">No files attached.</div>;
  return (
    <ul className="plain stack">
      {items.map((a) => (
        <li key={a.id} className="row row--base">
          <a className="lnk" href={href(a)} target="_blank" rel="noreferrer">{a.filename}</a>
          <span className="sub2">{a.content_type === "application/pdf" ? "PDF" : a.content_type === "image/png" ? "PNG" : "JPEG"} · {human(Number(a.bytes))} · {a.uploader_name} · {when(a.uploaded_at)}</span>
          {a.internal ? <Pil kind="grey">Internal</Pil> : null}
        </li>
      ))}
    </ul>
  );
}

/** what the category asked for, as the requester answered it */
export function DetailsGrid({ fields, details }: { fields: string; details: string }) {
  const fs = parse<Field[]>(fields, []);
  const d = parse<Record<string, string>>(details, {});
  const pairs: [string, ReactNode][] = fs.filter((f) => d[f.key]).map((f) => [f.label, f.type === "date" ? dayOf(d[f.key]) : d[f.key]]);
  for (const [k, v] of Object.entries(d)) if (!fs.some((f) => f.key === k) && v) pairs.push([k.replace(/_/g, " "), v]);
  if (!pairs.length) return <div className="sub2">Nothing beyond the subject and description.</div>;
  return <KvGrid pairs={pairs} cls="grid--3" />;
}
