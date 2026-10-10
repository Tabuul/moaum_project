"use client";

/**
 * V358: the amendments of published results waiting at this desk's stage, within its scope — each opened on its sheet's chain,
 * where the desk approves or refuses it.
 */
import { useEffect, useState } from "react";
import { LinkBtn, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

interface Waiting {
  id: string; ref: string; stage: string; sheet_id: string; raised_at: string; reason: string; course_code: string; session: string; semester: number;
  number: string; name: string; outcome: string; ca: number | null; exam: number | null; was_outcome: string; was_ca: number | null; was_exam: number | null;
}
const markOf = (o: string, ca: number | null, ex: number | null) => (o === "GRADED" ? `${ca ?? "—"} + ${ex ?? "—"}` : o.toLowerCase());

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
        <p className="sub2">Corrections of published results at your stage.</p>
        <DTable noPrint pageSize={20} cols={["Amendment", "Course", "Student", "Published → corrected", "Reason", "|mid"]} rows={rows.map((a) => [
          <b key="r" className="tnum">{a.ref}</b>, `${a.course_code} · ${a.session}, semester ${a.semester}`, <span key="s">{a.name}<span className="sub2 tnum" style={{ display: "block" }}>{a.number}</span></span>,
          <span key="m" className="tnum">{`${markOf(a.was_outcome, a.was_ca, a.was_exam)} → ${markOf(a.outcome, a.ca, a.exam)}`}</span>, <span key="w" className="sub2">{a.reason}</span>,
          <LinkBtn key="o" kind="primary" href={`/results/chain?sheet=${a.sheet_id}`}>Open</LinkBtn>])} />
      </PBody>
    </Panel>
  );
}
