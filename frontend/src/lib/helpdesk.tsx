/** ICT support tickets (V251): the shapes the API returns, and the small pieces every ticket screen shares —
 *  the status and priority pills, the history as a timeline, the attachments list, the category's fields. */
import type { ReactNode } from "react";
import { KvGrid, Pil } from "@/components/proto/ui";

export interface TicketRow {
  id: string; number: string; subject: string; status: string; priority: string; created_at: string; updated_at: string;
  resolved_at: string | null; closed_at: string | null; reopen_count: number;
  category_code: string; category: string; requester_kind: "STUDENT" | "STAFF"; requester_name: string; requester_number: string | null; requester_email: string | null;
  department_code: string | null; department: string | null; faculty_code: string | null; faculty: string | null;
  assigned_to: string | null; agent: string | null; escalated: boolean; due_at: string | null; overdue: boolean; response_overdue: boolean; attachments: number;
}
export interface Comment { id: string; author_kind: "REQUESTER" | "AGENT" | "SYSTEM"; author_name: string; internal: boolean; body: string; created_at: string }
export interface Attachment { id: string; comment_id: string | null; uploaded_kind: string; uploader_name: string; filename: string; content_type: string; bytes: number; internal: boolean; uploaded_at: string }
export interface Event { id?: string; at: string; actor_kind?: string; actor_name?: string; actor?: string; action: string; from_value: string | null; to_value: string | null; detail: string | null; internal?: boolean }
export interface Ticket extends Omit<TicketRow, "attachments"> {
  description: string; details: string; fields: string; attachment_hint: string | null; requester_phone: string | null;
  assigned_by_name: string | null; assigned_at: string | null;
  escalated_to_name: string | null; escalated_by_name: string | null; escalated_at: string | null; escalation_reason: string | null;
  opened_at: string | null; opened_by_name: string | null; first_response_at: string | null; in_progress_at: string | null; response_due_at: string | null;
  resolved_by_name: string | null; resolution_summary: string | null; resolution_details: string | null;
  closed_by_kind: string | null; closed_by_name: string | null; closure_reason: string | null;
  comments: Comment[]; attachments: Attachment[]; timeline: Event[];
}
export interface Field { key: string; label: string; type: "text" | "date" | "number" | "select" | "session" | "semester" | "level"; required?: boolean; options?: string[]; hint?: string }
export interface Category { id: string; code: string; name: string; description: string | null; suggested_priority: string; fields: string; attachment_hint: string | null; active?: boolean; ordinal?: number; tickets?: number }
export interface Profile { kind: "STUDENT" | "STAFF"; name: string; number: string | null; email: string | null; phone: string | null; department: string | null; departmentCode: string | null; faculty: string | null; facultyCode: string | null; programme: string | null; openTickets: number }
export interface Agent { id: string; name: string; staff_number: string | null; reachable: boolean; offices: string; director: boolean; open: number }

export const STATUS: Record<string, [string, "grey" | "info" | "ok" | "bad" | "warn"]> = {
  SUBMITTED: ["Submitted", "info"], OPENED: ["Opened", "info"], IN_PROGRESS: ["In progress", "warn"], RESOLVED: ["Resolved", "ok"], CLOSED: ["Closed", "grey"], REOPENED: ["Reopened", "bad"],
};
export const PRIORITY: Record<string, [string, "grey" | "info" | "ok" | "bad" | "warn"]> = {
  LOW: ["Low", "grey"], NORMAL: ["Normal", "info"], HIGH: ["High", "warn"], URGENT: ["Urgent", "bad"],
};
export const ACTION: Record<string, string> = {
  SUBMITTED: "Ticket submitted", OPENED: "Ticket opened", STATUS_CHANGED: "Status changed", ASSIGNED: "Assigned", REASSIGNED: "Reassigned", ESCALATED: "Escalated",
  PRIORITY_CHANGED: "Priority changed", INTERNAL_NOTE: "Internal note", UPDATE: "Update", RESOLUTION: "Resolution added", REOPENED: "Reopened", CLOSED: "Closed", ATTACHMENT: "Attachment added",
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
export interface Activity { id: string; at: string; actor_kind: string; actor_name: string; action: string; from_value: string | null; to_value: string | null; detail: string | null; internal: boolean; ticket_id: string; number: string; subject: string; status: string; priority: string }
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
const DESK_ONLY = new Set(["INTERNAL_NOTE", "ESCALATED", "PRIORITY_CHANGED"]);
const DESK_DETAIL = new Set(["ASSIGNED", "REASSIGNED"]);

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
          : e.action === "ASSIGNED" || e.action === "REASSIGNED" || e.action === "ESCALATED" ? [e.from_value, e.to_value].filter(Boolean).join(" → ")
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
