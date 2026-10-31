"use client";

/** V715: the latest corrections of postgraduate records — applicants' (the record page) and students' (the student edit page) — newest first */
import Link from "next/link";
import { Note, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { fieldWord, words, type RecentRow } from "@/lib/pg-records";

const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");

export function PgChangeHistory({ rows, limit }: { rows: RecentRow[]; limit: number }) {
  return (
    <Panel title="Postgraduate record changes" right={<span className="sub2">The latest {limit}, newest first · <Link href="/admissions/postgraduate/records">Find a record</Link></span>}>
      {!rows.length ? <PBody><Note kind="info" title="No correction yet">Corrections made on the postgraduate record page and the student edit page are listed here, with the value before and after and the reason.</Note></PBody> : null}
      {rows.length ? (
        <DTable pageSize={50} cols={["Date", "User", "Record", "Section|mid", "Field", "Old value", "New value", "Reason", "Source|mid"]} rows={rows.map((r) => [
          <span key="d" className="tnum">{when(r.at)}</span>,
          <span key="u">{r.by_name ?? "—"}{r.office ? <span className="sub2"> · {r.office}</span> : null}</span>,
          <span key="r"><Link href={r.kind === "STUDENT" ? `/students/${r.record_id}/edit?section=history` : `/admissions/postgraduate/applications/${r.record_id}/edit?section=history`}><b>{r.name}</b></Link>
            <span className="sub2 tnum"> · {r.number ?? "—"}</span> <Pil kind={r.kind === "STUDENT" ? "info" : "grey"}>{r.kind === "STUDENT" ? "Student" : "Applicant"}</Pil></span>,
          <Pil key="s" kind={r.severity === "CRITICAL" ? "bad" : "warn"}>{words(r.section)}</Pil>,
          fieldWord(r.field),
          <span key="o" style={{ whiteSpace: "pre-wrap" }}>{r.old_value ?? "—"}</span>,
          <span key="n" style={{ whiteSpace: "pre-wrap" }}>{r.new_value ?? "—"}</span>,
          <span key="w" className="sub2">{r.reason}</span>,
          <span key="src" className="sub2 tnum">{r.reference}</span>,
        ])} texts={rows.map((r) => `${r.name} ${r.number ?? ""} ${r.field} ${r.old_value ?? ""} ${r.new_value ?? ""} ${r.reason}`)} />
      ) : null}
    </Panel>
  );
}
