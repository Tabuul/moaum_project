"use client";

/**
 * What every allocation desk shows (V408): the checks before an allocation — catalogue.allocation_checks, each with ✓, ! or ✗
 * and its words — and the allocation history after it. The Head of Department's desk and the ICT desk draw them the same way.
 */
import { roleLabel } from "@/lib/offices";
import { DTable } from "@/components/proto/DTable";
import { Btn } from "@/components/proto/ui";

export interface AllocationCheck { code: string; level: "OK" | "WARNING" | "ERROR"; words: string }
export interface AllocationChecks { checks: AllocationCheck[]; ok: boolean; overload: boolean }
export interface AllocationEvent {
  id: string; offering_id: string; course_code: string; session: string; semester: number; action: string; role: string; reason: string | null; source: string;
  actor_office: string | null; at: string; lecturer: string | null; lecturer_staff_number: string | null; previous_lecturer: string | null; performed_by: string | null;
  ticket: string | null; department: string | null;
}

/** the checks no desk may override (the server refuses them too): the course and class, the session, the person active and teaching */
export const FIRM_CHECKS = new Set(["COURSE", "OFFERED", "SESSION", "LECTURER", "ACTIVE", "TEACHING"]);

export const ACTION_WORD: Record<string, string> = {
  ALLOCATED: "Allocated", REASSIGNED: "Reassigned", UNALLOCATED: "Lecturer removed", CO_LECTURER_ADDED: "Co-lecturer added", CO_LECTURER_REMOVED: "Co-lecturer removed",
  SECOND_EXAMINER_SET: "Second examiner named", SECOND_EXAMINER_REMOVED: "Second examiner removed", ON_RECORD: "On record",
};
export const ROLE_WORD: Record<string, string> = { LECTURER: "Lead lecturer", CO_LECTURER: "Co-lecturer", SECOND_EXAMINER: "Second examiner" };
export const SOURCE_WORD: Record<string, string> = { DESK: "Desk", IMPORT: "Bulk import", SYSTEM: "System" };

export const whenText = (iso: string) => new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" });
export const byText = (h: AllocationEvent) => (h.performed_by ? `${h.performed_by}${h.actor_office ? ` (${roleLabel(h.actor_office)})` : ""}` : SOURCE_WORD[h.source] ?? h.source);

/** an ERROR among the checks no desk may override */
export const firmError = (c: AllocationChecks | null) => !!c && c.checks.some((x) => x.level === "ERROR" && FIRM_CHECKS.has(x.code));

const MARK: Record<AllocationCheck["level"], [string, string, string]> = {
  OK: ["✓", "var(--green-ink, #1d7a46)", "Passed"], WARNING: ["!", "var(--amber-ink, #a15c00)", "Note"], ERROR: ["✗", "var(--red-ink, #c51e28)", "Refused"],
};

/** the checks, one line each */
export function CheckList({ checks, title }: { checks: AllocationChecks | null; title?: string }) {
  if (!checks) return <p className="sub2 mt-1">Checking…</p>;
  return (
    <div className="mt-1">
      {title ? <div className="eyebrow">{title}</div> : null}
      <ul style={{ listStyle: "none", padding: 0, margin: "4px 0 0" }}>
        {checks.checks.map((c) => (
          <li key={c.code} style={{ display: "flex", gap: 8, alignItems: "baseline", padding: "2px 0" }}>
            <span aria-label={MARK[c.level][2]} style={{ color: MARK[c.level][1], fontWeight: 700, minWidth: 12 }}>{MARK[c.level][0]}</span>
            <span>{c.words}</span>
          </li>
        ))}
      </ul>
    </div>
  );
}

/** the allocation history: with showCourse, the course of each row (a department's or a desk's list), else one class's */
export function HistoryTable({ rows, showCourse, onOpen, pageSize = 10 }: { rows: AllocationEvent[]; showCourse?: boolean; onOpen?: (offering: string) => void; pageSize?: number }) {
  if (!rows.length) return <p className="sub2">No allocation recorded yet.</p>;
  return (
    <DTable noPrint={!showCourse} pageSize={pageSize}
      cols={["S/N|num", "When", ...(showCourse ? ["Course"] : []), "Action", "Role", "Lecturer", "Previous", "Reason", "By", "Ticket", ...(onOpen ? ["|mid"] : [])]}
      texts={showCourse ? rows.map((h) => `${h.course_code} ${h.lecturer ?? ""} ${h.previous_lecturer ?? ""} ${h.reason ?? ""} ${h.performed_by ?? ""} ${h.ticket ?? ""}`) : undefined}
      rows={rows.map((h, i) => [i + 1, whenText(h.at), ...(showCourse ? [<b key="c">{h.course_code}</b>] : []), ACTION_WORD[h.action] ?? h.action, ROLE_WORD[h.role] ?? h.role,
        h.lecturer || "—", h.previous_lecturer || "—", h.reason ?? "—", byText(h), h.ticket ?? "—",
        ...(onOpen ? [<Btn key="o" kind="ghost" onClick={() => onOpen(h.offering_id)}>View</Btn>] : [])])} />
  );
}
