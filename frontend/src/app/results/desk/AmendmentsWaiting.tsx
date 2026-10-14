"use client";

/**
 * V358: the amendments of published results waiting at this desk's stage, within its scope — each opened on its sheet's chain,
 * where the desk approves or refuses it. V422: a late result (a candidate on the roll with no mark before) waits here the same way;
 * V465: so does a units correction for one programme's students on an examined class.
 */
import { useEffect, useState } from "react";
import { LinkBtn, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

interface Waiting {
  id: string; ref: string; kind?: "AMEND" | "LATE" | "UNITS"; stage: string; sheet_id: string; raised_at: string; reason: string; course_code: string; session: string; semester: number;
  number: string | null; name: string | null; outcome: string | null; ca: number | null; exam: number | null; was_outcome: string | null; was_ca: number | null; was_exam: number | null;
  programme_code?: string | null; programme_name?: string | null; units?: number | null; was_units?: number | null;
}
const unitsOf = (n: number | null | undefined) => (n == null ? "—" : `${n} unit${n === 1 ? "" : "s"}`);
const markOf = (o: string | null, ca: number | null, ex: number | null) => (o == null ? "no mark" : o === "GRADED" ? `${ca ?? "—"} + ${ex ?? "—"}` : o.toLowerCase());

export function AmendmentsWaiting() {
  const [rows, setRows] = useState<Waiting[] | null>(null);
  useEffect(() => {
    let live = true;
    void fetch("/api/bff/api/v1/results/amendments", { cache: "no-store" }).then(async (r) => { if (live) setRows(r.ok ? await r.json() : []); });
    return () => { live = false; };
  }, []);
  if (!rows || !rows.length) return null;
  return (
    <Panel title="Amendments waiting on this desk" right={<Pil kind="warn">{`${rows.length} to decide`}</Pil>}>
      <PBody>
        <p className="sub2">Corrections of published results, late results for candidates with no mark on a published sheet, and units corrections for a programme&rsquo;s students on an examined class, at your stage.</p>
        <DTable noPrint pageSize={20} cols={["Amendment", "Course", "Student", "Published → corrected", "Reason", "|mid"]} rows={rows.map((a) => [
          <span key="r"><b className="tnum">{a.ref}</b>{a.kind === "LATE" ? <span className="sub2" style={{ display: "block" }}>Late result</span> : a.kind === "UNITS" ? <span className="sub2" style={{ display: "block" }}>Units</span> : null}</span>, `${a.course_code} · ${a.session}, semester ${a.semester}`,
          a.kind === "UNITS" ? <span key="s">{`Students of ${a.programme_code}`}<span className="sub2" style={{ display: "block" }}>{a.programme_name ?? ""}</span></span>
            : <span key="s">{a.name}<span className="sub2 tnum" style={{ display: "block" }}>{a.number}</span></span>,
          <span key="m" className="tnum">{a.kind === "UNITS" ? `${unitsOf(a.was_units)} → ${unitsOf(a.units)}` : `${markOf(a.was_outcome, a.was_ca, a.was_exam)} → ${markOf(a.outcome, a.ca, a.exam)}`}</span>, <span key="w" className="sub2">{a.reason}</span>,
          <LinkBtn key="o" kind="primary" href={`/results/chain?sheet=${a.sheet_id}`}>Open</LinkBtn>])} />
      </PBody>
    </Panel>
  );
}
