"use client";

/**
 * V358: the amendments of published results waiting at this desk's stage, within its scope — each opened on its sheet's chain,
 * where the desk approves or refuses it. V422: a late result (a candidate on the roll with no mark before) waits here the same way;
 * V465: so does a units correction for one programme's students on an examined class. The list prints (PDF) and downloads
 * (Excel) for the meeting that decides it — at the Senate desk, the Senate's list: each amendment with its reason, who raised
 * it, every approval before it, and a column for the Senate's decision and the minute that applies it.
 */
import { useEffect, useState } from "react";
import { Btn, LinkBtn, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { roleLabel } from "@/lib/offices";
import { STAGE_LABEL } from "@/lib/results";

interface Decision { kind: string; from: string | null; to: string; office: string | null; comment: string | null; at: string; by: string | null }
interface Waiting {
  id: string; ref: string; kind?: "AMEND" | "LATE" | "UNITS"; stage: string; sheet_id: string; raised_at: string; reason: string; course_code: string; session: string; semester: number;
  number: string | null; name: string | null; outcome: string | null; ca: number | null; exam: number | null; was_outcome: string | null; was_ca: number | null; was_exam: number | null;
  programme_code?: string | null; programme_name?: string | null; units?: number | null; was_units?: number | null;
  raised_by_name?: string | null; raised_office?: string | null; decisions?: Decision[];
}
const unitsOf = (n: number | null | undefined) => (n == null ? "—" : `${n} unit${n === 1 ? "" : "s"}`);
const markOf = (o: string | null, ca: number | null, ex: number | null) => (o == null ? "no mark" : o === "GRADED" ? `${ca ?? "—"} + ${ex ?? "—"}` : o.toLowerCase());
const day = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—");
const KIND: Record<string, string> = { AMEND: "Mark correction", LATE: "Late result", UNITS: "Units correction" };
const stageName = (s: string | null | undefined) => (s ? STAGE_LABEL[s]?.[0] ?? s.toLowerCase().replace(/_/g, " ") : "—");

export function AmendmentsWaiting({ stage }: { stage?: string }) {
  const [rows, setRows] = useState<Waiting[] | null>(null);
  useEffect(() => {
    let live = true;
    void fetch("/api/bff/api/v1/results/amendments", { cache: "no-store" }).then(async (r) => { if (live) setRows(r.ok ? await r.json() : []); });
    return () => { live = false; };
  }, []);
  if (!rows || !rows.length) return null;

  // the printed list: the Senate's agenda at the Senate desk, else this desk's list
  const senate = stage === "SENATE" || rows.every((a) => a.stage === "SENATE");
  const title = senate ? "Result amendments for Senate" : `Result amendments at ${stageName(stage ?? rows[0].stage)}`;
  const HEAD = ["S/N", "Amendment", "Kind", "Course", "Session", "Student or programme", "Published", "Corrected to", "Reason", "Raised by", "Approvals", senate ? "Senate decision and minute" : "Decision"];
  const list = () => [...rows].sort((a, b) => a.course_code.localeCompare(b.course_code) || a.ref.localeCompare(b.ref)).map((a, i) => [
    i + 1, a.ref, KIND[a.kind ?? "AMEND"] ?? a.kind ?? "", a.course_code, `${a.session}, semester ${a.semester}`,
    a.kind === "UNITS" ? `Students of ${a.programme_code}${a.programme_name ? ` (${a.programme_name})` : ""}` : `${a.name ?? ""} ${a.number ?? ""}`.trim(),
    a.kind === "UNITS" ? unitsOf(a.was_units) : markOf(a.was_outcome, a.was_ca, a.was_exam),
    a.kind === "UNITS" ? unitsOf(a.units) : markOf(a.outcome, a.ca, a.exam),
    a.reason, `${a.raised_by_name ?? "—"} (${roleLabel(a.raised_office ?? null)}), ${day(a.raised_at)}`,
    // each approval named by what it did — the stage it moved the amendment to ("Verified", "Departmental approved", …)
    (a.decisions ?? []).filter((d) => d.kind === "ADVANCE").map((d) => `${stageName(d.to)}: ${d.by ?? roleLabel(d.office)}, ${day(d.at)}`).join("; ") || "—",
    "",
  ]);
  const meta = (): [string, string][] => [["Stage", senate ? "Senate" : stageName(stage ?? rows[0].stage)], ["Amendments", String(rows.length)], ["Listed", day(new Date().toISOString())]];
  const footnote = senate
    ? "Each amendment approved is applied by the Registrar on the Senate minute cited for it; one refused is closed with the reason. A published mark is never overwritten: the correction is a new version, the original kept."
    : "Each amendment is approved or refused on its sheet's chain, by this desk, with the reason for a refusal.";

  return (
    <Panel title="Amendments waiting on this desk" right={<span className="row row--inline row--tight">
      <Pil kind="warn">{`${rows.length} to decide`}</Pil>
      <Btn kind="ghost" size="sm" onClick={async () => downloadBlob(await brandedXlsx(title, HEAD, list(), { sheetName: "Amendments", serial: docSerial("AMD"), meta: meta() }), senate ? "amendments-for-senate.xlsx" : "amendments-waiting.xlsx")}>Excel</Btn>
      <Btn kind="ghost" size="sm" onClick={() => brandedPrint(title, `${rows.length} amendment${rows.length === 1 ? "" : "s"} to decide`, HEAD, list(), docSerial("AMD"), { meta: meta(), footnote, orientation: "landscape" })}>{senate ? "Print for Senate" : "PDF"}</Btn>
    </span>}>
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
