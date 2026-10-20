"use client";

/** every placement a record has had, as people.programme_history reads it: the admission, transfers, record moves, swaps, and any other
 *  change of programme on the audit chain — oldest first, the current one marked (V578) */
import { DTable } from "@/components/proto/DTable";
import { Pil } from "@/components/proto/ui";
import { day } from "@/components/proto/blocks";
import { words } from "@/lib/full-record";

const KINDS: Record<string, string> = {
  ORIGINAL_ADMISSION: "Original admission", TRANSFER_EFFECTED: "Inter-departmental transfer", RECORD_MOVED: "Record moved", PROGRAMME_CHANGED: "Programme changed on the record",
  PROGRAMME_SWAP_LEGACY_MIGRATION_CORRECTION: "Programme swap: legacy migration correction", PROGRAMME_SWAP_PROGRAMME_CORRECTION: "Programme swap: programme correction",
  PROGRAMME_SWAP_ACADEMIC_TRANSFER: "Programme swap: academic transfer recorded",
};

export function ProgrammeHistory({ rows }: { rows: Record<string, unknown>[] }) {
  if (!rows.length) return <div className="sub2">No placement on record.</div>;
  return (
    <DTable pageSize={0} cols={["When", "Programme", "Department", "Faculty", "What", "From", "By"]}
      rows={rows.map((h) => [
        <span key="w" className="tnum">{h.at ? day(String(h.at)) : "—"}{h.session ? <div className="sub2">{String(h.session)}</div> : null}</span>,
        <span key="p"><b>{String(h.programme ?? h.programme_code ?? "—")}</b>{h.current ? <> <Pil kind="ok">Current</Pil></> : null}<div className="sub2 tnum">{String(h.programme_code ?? "")}</div></span>,
        String(h.department ?? h.dept_code ?? "—"), String(h.faculty ?? h.faculty_code ?? "—"),
        <span key="k">{KINDS[String(h.kind)] ?? words(h.kind)}{h.detail && h.kind !== "ORIGINAL_ADMISSION" ? <div className="sub2">{String(h.detail)}</div> : null}{h.reference ? <div className="sub2 tnum">{String(h.reference)}</div> : null}</span>,
        <span key="f" className="sub2">{h.from_programme ? `${h.from_programme}${h.from_level ? ` · ${h.from_level} Level` : ""}` : "—"}</span>,
        <span key="b" className="sub2">{String(h.by_whom ?? "—")}</span>,
      ])} />
  );
}
