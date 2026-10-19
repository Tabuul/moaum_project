/** Student 360° — the full record (Oct 2026). The shapes /api/v1/student/students/{id}/full/{section} returns, the words a record's
 *  values are shown in, and the tables the print and the downloads take. Every figure is the one a module holds: nothing here
 *  computes a level, a result or a payment the record does not carry, and a missing result is never a zero. */

export type Section = "overview" | "admission" | "progression" | "registrations" | "results" | "finance" | "hostel" | "clearance" | "documents"
  | "support" | "audit";
/** the tabs: the record's sections as the server reads them, with the biodata and the notifications the page already holds */
export type Tab = Section | "biodata" | "notifications";

export const TAB_LABELS: Record<Tab, string> = {
  overview: "Overview", biodata: "Biodata", admission: "Admission", progression: "Level progression", registrations: "Course registration",
  results: "Results", finance: "Fees and payments", hostel: "Hostel", clearance: "Clearance", documents: "Documents", support: "ICT support",
  notifications: "Notifications", audit: "Activity",
};
const ORDER: Tab[] = ["overview", "biodata", "admission", "progression", "registrations", "results", "finance", "hostel", "clearance", "documents",
  "support", "notifications", "audit"];

/** the tabs this office sees: the sections the server says it reads, the biodata always, the notifications where the page offers them */
export function tabsFor(sections: string[], messages: boolean): Tab[] {
  return ORDER.filter((t) => t === "biodata" || (t === "notifications" ? messages : sections.includes(t)));
}
export function tabOf(v: string | null | undefined, tabs: Tab[]): Tab {
  return tabs.includes(v as Tab) ? (v as Tab) : "overview";
}

type Row = Record<string, unknown>;
export interface Held { session: string; semester: number | null; level: number | null; source: "ENROLMENT" | "REGISTRATION"; detail: string | null; at: string | null }
export interface Change { at: string; actor_office: string | null; actor: string | null; reason: string | null; previous_level: number | null; new_level: number | null;
  previous_programme: string | null; new_programme: string | null; previous_status: string | null; new_status: string | null }
export interface Decision { decided_at: string; rule: string | null; previous_status: string | null; final_status: string | null; previous_level: number | null;
  new_level: number | null; previous_cohort: string | null; effective_cohort: string | null; reason: string | null; batch_ref: string | null; actor_office: string | null;
  officer: string | null }
export interface StatusChange { id: number; from_status: string | null; to_status: string; instrument: string | null; effective_on: string; expires_on: string | null; reason: string | null }
export interface Progression { held: Held[]; changes: Change[]; decisions: Decision[]; statuses: StatusChange[]; deferments: Row[]; position: Row | null }

/** the names the University writes in capitals stay so (UTME, not Utme) */
const ACRONYMS = new Set(["UTME", "DE", "JUPEB", "IJMB", "CCE", "PG", "SIWES", "GST", "EPS", "HOD", "ICT", "NELFUND", "CAPS", "JAMB", "NCE", "ND", "HND", "OND", "CGPA", "GPA", "SP1", "SP2"]);
/** a code in words, sentence case: FULLY_PAID → Fully paid, DIRECT_ENTRY → Direct entry, UTME → UTME */
export const words = (v: unknown) => String(v ?? "").split("_").filter(Boolean)
  .map((w, i) => (ACRONYMS.has(w.toUpperCase()) ? w.toUpperCase() : i === 0 ? w.charAt(0).toUpperCase() + w.slice(1).toLowerCase() : w.toLowerCase())).join(" ");
export const day = (v: unknown) => (v ? new Date(String(v)).toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "numeric" }) : "");
export const naira = (v: unknown) => `₦${Number(v ?? 0).toLocaleString("en-GB", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
const semWord = (n: unknown) => (n === 1 ? "First" : n === 2 ? "Second" : n === 3 ? "Third" : n == null ? "" : `Semester ${n}`);

/** the level the student was at in each session the record holds — from the enrolment and the course registrations, as recorded;
 *  a session with neither is not on the list (no level is filled in), and one whose records disagree says so */
export function levelHistory(p: Pick<Progression, "held">): { session: string; level: number | null; levels: number[]; semesters: string; source: string; conflict: boolean }[] {
  const by = new Map<string, Held[]>();
  for (const h of p.held) by.set(h.session, [...(by.get(h.session) ?? []), h]);
  return Array.from(by.entries()).sort(([a], [b]) => a.localeCompare(b)).map(([session, hs]) => {
    const enrolment = hs.find((h) => h.source === "ENROLMENT" && h.level != null);
    const levels = Array.from(new Set(hs.map((h) => h.level).filter((l): l is number => l != null))).sort((x, y) => x - y);
    const regs = hs.filter((h) => h.source === "REGISTRATION");
    return {
      session,
      level: enrolment?.level ?? (levels.length === 1 ? levels[0] : null),
      levels,
      semesters: regs.map((r) => `${semWord(r.semester)} (${words(r.detail)})`).join(", "),
      source: [enrolment ? "Enrolment" : "", regs.length ? "Course registration" : ""].filter(Boolean).join(" and "),
      conflict: levels.length > 1,
    };
  });
}

export interface TimelineEvent { at: string; kind: "LEVEL" | "PROGRAMME" | "STATUS" | "COHORT" | "DEFERMENT"; text: string; by: string | null; reason: string | null }

/** every change of level, programme, status or cohort as it was recorded (the audit chain's rows, the cohort decisions, the
 *  instruments of a change of status, the deferments), oldest first — nothing inferred between them */
export function timeline(p: Progression): TimelineEvent[] {
  const out: TimelineEvent[] = [];
  for (const c of p.changes) {
    const by = c.actor ? `${c.actor}${c.actor_office && c.actor_office !== "student" ? ` (${c.actor_office})` : ""}` : null;
    if (c.previous_level !== c.new_level) out.push({ at: c.at, kind: "LEVEL", text: `Level ${c.previous_level ?? "—"} → ${c.new_level ?? "—"}`, by, reason: c.reason });
    if (c.previous_programme !== c.new_programme) out.push({ at: c.at, kind: "PROGRAMME", text: `Programme ${c.previous_programme ?? "—"} → ${c.new_programme ?? "—"}`, by, reason: c.reason });
    if (c.previous_status !== c.new_status) out.push({ at: c.at, kind: "STATUS", text: `Status ${words(c.previous_status) || "—"} → ${words(c.new_status)}`, by, reason: c.reason });
  }
  for (const d of p.decisions) {
    const parts = [d.previous_level !== d.new_level && d.new_level != null ? `level ${d.previous_level ?? "—"} → ${d.new_level}` : "",
      d.previous_status !== d.final_status && d.final_status ? `status ${words(d.previous_status) || "—"} → ${words(d.final_status)}` : "",
      d.previous_cohort !== d.effective_cohort && d.effective_cohort ? `cohort ${d.previous_cohort ?? "—"} → ${d.effective_cohort}` : ""].filter(Boolean);
    out.push({ at: d.decided_at, kind: "COHORT", text: `Cohort decision${d.rule ? ` (${words(d.rule)})` : ""}${parts.length ? `: ${parts.join(", ")}` : ""}`,
      by: d.officer ? `${d.officer}${d.actor_office ? ` (${d.actor_office})` : ""}` : d.actor_office, reason: [d.reason, d.batch_ref ? `batch ${d.batch_ref}` : ""].filter(Boolean).join(" · ") || null });
  }
  for (const s of p.statuses) {
    out.push({ at: s.effective_on, kind: "STATUS", text: `Status ${words(s.from_status) || "—"} → ${words(s.to_status)} on ${s.instrument ?? "no instrument named"}`, by: null, reason: s.reason });
  }
  for (const d of p.deferments) {
    out.push({ at: String(d.created_at), kind: "DEFERMENT", text: `${words(d.kind) || "Deferment"} ${d.reference ?? ""} for ${d.session ?? ""}${d.semester ? ` semester ${d.semester}` : ""}: ${words(d.state)}`.replace(/\s+/g, " ").trim(),
      by: null, reason: d.return_session ? `returns ${d.return_session}${d.return_semester ? ` semester ${d.return_semester}` : ""}` : null });
  }
  return out.filter((e) => e.at).sort((a, b) => String(a.at).localeCompare(String(b.at)));
}

export interface ResultRow { session: string; semester: number; course_code: string; title: string; units: number; entry_type: string | null; stage: string; published: boolean;
  published_at: string | null; ca: number | null; exam: number | null; total: number | null; grade: string | null; points: number | null; outcome: string | null }

/** a result as the results engine holds it: the grade when published; otherwise where the sheet is — never a zero, never a fail */
export function resultWord(r: Pick<ResultRow, "published" | "stage" | "grade" | "outcome">): string {
  if (r.published) return r.outcome === "ABSENT" ? "F (absent)" : r.grade ?? "Published";
  if (r.stage === "NO_RESULT") return "No result";
  if (r.stage === "NO_SHEET") return "Not yet submitted";
  return `Awaiting approval (${words(r.stage)})`;
}

export interface Payment { id: string; session: string | null; reference: string; purpose: string | null; amount: number | string; generated_at: string; expires_at: string | null;
  confirmed_at: string | null; channel: string | null; receipt_no: string | null; term: string | null; status: "PAID" | "PENDING" | "EXPIRED"; school_fees: boolean;
  gateway: string | null; gateway_ref: string | null; gateway_outcome: string | null; note?: string | null }

export const PAYMENT_WORDS: Record<Payment["status"], string> = { PAID: "Paid", PENDING: "Pending", EXPIRED: "Expired, not paid" };

/** a table for the print and the downloads: the title, the columns (S/N first) and the rows */
export interface Table { title: string; headers: string[]; rows: (string | number)[][] }
const n = (rows: (string | number)[][]) => rows.map((r, i) => [i + 1, ...r]);

/** the tables a section prints and downloads — the section's data as the server sent it */
export function sectionTables(section: Section, d: Record<string, unknown> | null | undefined): Table[] {
  if (!d) return [];
  const a = (k: string) => ((d[k] ?? []) as Row[]);
  switch (section) {
    case "progression": {
      const p = d as unknown as Progression;
      return [
        { title: "Level by session", headers: ["S/N", "Session", "Level", "Semesters registered", "Recorded by"],
          rows: n(levelHistory(p).map((h) => [h.session, h.conflict ? h.levels.join(" / ") : h.level ?? "", h.semesters, h.source])) },
        { title: "Changes of level, programme, status and cohort", headers: ["S/N", "Date", "Change", "By", "Reason"],
          rows: n(timeline(p).map((e) => [day(e.at), e.text, e.by ?? "", e.reason ?? ""])) },
      ];
    }
    case "registrations":
      return [
        { title: "Course registrations", headers: ["S/N", "Session", "Semester", "Level", "Status", "Units", "Courses", "Submitted", "Approved"],
          rows: n(a("registrations").map((r) => [String(r.session), semWord(r.semester), Number(r.level ?? 0) || "", words(r.status), Number(r.units ?? 0),
            ((r.courses ?? []) as Row[]).map((c) => `${c.course_code} (${c.units})`).join(", "), day(r.submitted_at), day(r.approved_at)])) },
        { title: "Registrations reset (each version kept)", headers: ["S/N", "Session", "Semester", "Level", "Was", "Courses", "Units", "Reset on", "By", "Reason"],
          rows: n(a("resets").map((z) => [String(z.session), semWord(z.semester), Number(z.level ?? 0) || "", words(z.previous_status), Number(z.course_count ?? 0),
            Number(z.units ?? 0), day(z.reset_at), String(z.reset_by ?? z.reset_office ?? ""), String(z.reason ?? "")])) },
      ];
    case "results":
      return [
        { title: "Results", headers: ["S/N", "Session", "Semester", "Course", "Title", "Units", "CA", "Exam", "Total", "Grade or state"],
          rows: n((a("results") as unknown as ResultRow[]).map((r) => [r.session, semWord(r.semester), r.course_code, r.title, r.units,
            r.published && r.ca != null ? r.ca : "", r.published && r.exam != null ? r.exam : "", r.published && r.total != null ? r.total : "", resultWord(r)])) },
        { title: "Grade point averages", headers: ["S/N", "Session", "Semester", "Units", "GPA", "CGPA", "Published", "Registered"],
          rows: n(a("semesters").map((g) => [String(g.session), semWord(g.semester), Number(g.units ?? 0), g.gpa == null ? "" : Number(g.gpa).toFixed(2),
            g.cgpa == null ? "" : Number(g.cgpa).toFixed(2), Number(g.published_count ?? 0), Number(g.registered_count ?? 0)])) },
        { title: "Courses still owed", headers: ["S/N", "Course", "Title", "Units", "Failed in"],
          rows: n(a("owed").map((c) => [String(c.course_code), String(c.title ?? ""), Number(c.units ?? 0), String(c.failed_in ?? "")])) },
      ];
    case "finance":
      return [
        { title: "Payments", headers: ["S/N", "Date", "Session", "Purpose", "Reference", "Amount (₦)", "Status", "Channel", "Receipt"],
          rows: n((a("payments") as unknown as Payment[]).map((p) => [day(p.confirmed_at ?? p.generated_at), p.session ?? "", p.purpose ?? "", p.reference,
            Math.round(Number(p.amount) * 100) / 100, PAYMENT_WORDS[p.status] ?? p.status, p.channel ?? "", p.receipt_no ?? ""])) },
        { title: "School fees by session", headers: ["S/N", "Session", "Due (₦)", "Paid (₦)", "Outstanding (₦)", "Position"],
          rows: n(a("schoolFees").map((s) => [String(s.session), Number(s.payable ?? 0), Number(s.paid ?? 0), Number(s.outstanding ?? 0), words(s.status)])) },
        { title: "Refunds", headers: ["S/N", "Reference", "Amount (₦)", "State", "Raised", "Paid", "Reason"],
          rows: n(a("refunds").map((f) => [String(f.reference ?? ""), Number(f.amount ?? 0), words(f.state), day(f.created_at), day(f.paid_at), String(f.reason ?? "")])) },
      ];
    case "admission":
      return [
        { title: "Applications", headers: ["S/N", "Application", "Session", "Submitted", "Screening score", "Decision", "Accepted", "Cleared"],
          rows: n(a("applications").map((x) => [String(x.application_no ?? ""), String(x.session ?? ""), day(x.submitted_at), x.screening_score == null ? "" : Number(x.screening_score),
            words(x.decision), day(x.accepted_at), day(x.cleared_at)])) },
        { title: "Admission fees", headers: ["S/N", "Fee", "Reference", "Amount (₦)", "Confirmed", "Receipt"],
          rows: n(a("fees").map((f) => [words(f.kind), String(f.reference ?? ""), Number(f.amount ?? 0), day(f.confirmed_at) || "Not paid", String(f.receipt_no ?? "")])) },
        { title: "Changes of programme", headers: ["S/N", "Session", "From", "To", "State", "Requested", "Decided", "Note"],
          rows: n([...a("programmeChanges").map((r) => [String(r.session ?? ""), String(r.from_programme ?? r.from_programme_code ?? ""), String(r.to_programme ?? r.to_programme_code ?? ""),
            words(r.state), day(r.requested_at), day(r.decided_at), String(r.decision_note ?? "")]),
          ...a("transfers").map((t) => [String(t.session ?? ""), String(t.from_programme ?? t.from_programme_code ?? ""), String(t.to_programme ?? t.to_programme_code ?? ""),
            `Transfer: ${words(t.state)}`, day(t.applied_at), day(t.effected_at ?? t.senate_at), String(t.senate_note ?? "")])]) },
      ];
    case "hostel":
      return [{ title: "Hostel", headers: ["S/N", "Session", "Application", "Allocation", "Hall", "Room", "Bed", "Allocated", "Checked in", "Checked out"],
        rows: n(a("history").map((h) => [String(h.session ?? ""), `${h.application_ref ?? ""} ${words(h.application_state)}`.trim(), `${h.allocation_ref ?? ""} ${words(h.allocation_state)}`.trim(),
          String(h.hall_name ?? ""), [h.block, h.room_no].filter(Boolean).join(" "), String(h.bed_label ?? h.bed ?? ""), day(h.allocated_at), day(h.checked_in_at), day(h.checked_out_at)])) }];
    case "clearance":
      return [{ title: "Clearance", headers: ["S/N", "Clearance", "Unit", "State", "Decided", "Note"],
        rows: n([...a("processes").flatMap((p) => ((p.items ?? []) as Row[]).map((i) => [`${p.workflow_label ?? p.workflow} ${p.reference ?? ""}`.trim(), String(i.unit ?? ""), words(i.state),
          day(i.decided_at), String(i.note ?? i.item ?? "")])),
        ...a("items").map((i) => [words(i.purpose), String(i.unit ?? ""), words(i.state), day(i.decided_at), String(i.note ?? i.item ?? "")])]) }];
    case "documents":
      return [
        { title: "Admission documents", headers: ["S/N", "Document", "Detail", "Received", "Status"],
          rows: n(a("admission").map((x) => [words(x.kind), String(x.detail ?? ""), day(x.received_on), words(x.status)])) },
        { title: "Documents issued", headers: ["S/N", "Document", "Verification code", "Issued", "Office", "State"],
          rows: n(a("issued").map((x) => [words(x.kind), String(x.verification_code ?? ""), day(x.issued_on), String(x.issued_office ?? ""),
            x.revoked ? "Revoked" : x.reissue ? "Reissue" : "Issued"])) },
      ];
    case "support":
      return [
        { title: "Support tickets", headers: ["S/N", "Ticket", "Category", "Subject", "Status", "Raised", "Resolved"],
          rows: n(a("tickets").map((t) => [String(t.number ?? ""), String(t.category ?? ""), String(t.subject ?? ""), words(t.status), day(t.created_at), day(t.resolved_at)])) },
        { title: "Support actions on the record", headers: ["S/N", "Date", "Action", "Summary", "Agent", "Reason"],
          rows: n(a("actions").map((x) => [day(x.at), words(x.action), String(x.summary ?? ""), String(x.agent ?? x.agent_office ?? ""), String(x.reason ?? "")])) },
      ];
    case "audit":
      return [{ title: "Activity on the record", headers: ["S/N", "Date", "Activity", "By", "Changed", "Reason"],
        rows: n(a("activity").map((x) => [day(x.at), activityWord(String(x.kind ?? ""), String(x.subject ?? "")), `${x.actor ?? ""}${x.actor_office ? ` (${x.actor_office})` : ""}`,
          String(x.changed ?? x.reference ?? ""), String(x.reason ?? "")])) }];
    default:
      return [];
  }
}

const SUBJECTS: Record<string, string> = { "people.student": "the record", "people.student_contact": "the contact details", "registration.course_registration": "a course registration" };
/** an entry on the activity list, in words */
export function activityWord(kind: string, subject: string): string {
  if (kind.startsWith("RECORD_")) {
    const what = SUBJECTS[subject] ?? subject;
    return kind === "RECORD_INSERT" ? `Created ${what}` : kind === "RECORD_DELETE" ? `Removed ${what}` : `Changed ${what}`;
  }
  if (kind.startsWith("SUPPORT_")) return `ICT support: ${words(kind.slice(8))}`;
  if (kind.startsWith("PAYMENT_SWAP_")) return `Payment reallocation: ${words(kind.slice(13))}`;
  if (kind.startsWith("DOCUMENT_ISSUED_")) return `Issued: ${words(kind.slice(16))}`;
  if (kind === "MATRICULATION_ISSUED") return "Matriculation number issued";
  return words(kind);
}

const esc = (x: unknown) => String(x ?? "").replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c] ?? c));

/** the printed record: each chosen section's tables under its heading, a section with nothing recorded saying so */
export function printBody(parts: { label: string; tables: Table[]; facts?: [string, string][] }[]): string {
  return parts.map((p) => {
    const facts = p.facts && p.facts.length
      ? `<table><tbody>${p.facts.map(([k, v]) => `<tr><td style="width:34%;color:#5a6b74">${esc(k)}</td><td><b>${esc(v)}</b></td></tr>`).join("")}</tbody></table>` : "";
    const tables = p.tables.map((t) => `<h3 style="font-size:11px;margin:10px 0 4px;text-transform:uppercase;letter-spacing:.04em">${esc(t.title)}</h3>${t.rows.length
      ? `<table><thead><tr>${t.headers.map((h, i) => `<th${i === 0 ? ' class="sn"' : ""}>${esc(h)}</th>`).join("")}</tr></thead><tbody>${t.rows.map((r) =>
        `<tr>${r.map((c, i) => `<td${i === 0 ? ' class="sn"' : typeof c === "number" ? ' class="n"' : ""}>${esc(typeof c === "number" && i > 0 ? c.toLocaleString("en-GB") : c)}</td>`).join("")}</tr>`).join("")}</tbody></table>`
      : `<div style="color:#5a6b74;font-size:10.5px">None recorded.</div>`}`).join("");
    return `<section style="page-break-inside:auto;margin-bottom:14px"><h2 style="font-size:12.5px;margin:14px 0 6px;color:#0d3f54;border-bottom:1px solid #c9d3d9;padding-bottom:3px">${esc(p.label)}</h2>${facts}${tables}</section>`;
  }).join("");
}
