"use client";

/** V726: the legacy school-fee duplicate cleanup run on deployment — a record repeating another on all six fields (the old portal's
 *  payment number, the payment day, the student, the level, the semester, the session) deleted for good, one kept per group — with
 *  each run's actual counts and checks, and the groups left whole for the Bursary because their records conflict or are tied to
 *  something. Read-only: the cleanup runs as a migration on deployment, never from this page. */
import { useEffect, useState } from "react";
import type { Problem } from "@/lib/api";
import { notifyProblem } from "@/components/proto/Toast";
import { Btn, Note, Panel, PBody } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { money } from "@/components/proto/blocks";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";

interface Run {
  run_ref: string; run_by: string; database_name: string; started_at: string; finished_at: string; status: "DELETED" | "NOTHING_TO_DELETE" | "FAILED";
  inspected: number; groups_found: number; groups_cleaned: number; retained: number; deleted: number; groups_skipped: number; records_skipped: number;
  skipped_by_reason: string; amount_deleted: number | string; students: number; numbers_sealed: number; ledger_moved: number; ledger_released: number;
  identities_moved: number; receipts_voided: number; reconciliation: string; integrity: string; checks: string; error: string | null;
}
interface LeftWhole {
  group_key: string; reference: string; matric_no: string | null; session: string; level: number | null; semester: number; paid_on: string;
  payref: string; amount: number | string; role: string; reason: string; kept_reference: string;
}
interface Cleanup { runs: Run[]; now: { groups: number; deletable: number; groupsLeftWhole: number; recordsLeftWhole: number }; leftWhole: LeftWhole[] }

const REASONS: Record<string, string> = {
  AMOUNTS_DIFFER: "The amounts differ",
  ARCHIVED_OR_UNDER_REVIEW: "A record is archived or under review",
  EVIDENCE_ON_TWO_RECORDS: "Verified evidence names two records",
  EVIDENCE_ON_A_DUPLICATE: "Evidence names a record that would go",
  ANOTHER_PAYMENT_NUMBER: "A record carries another payment number",
  LINKED_RECORD: "A record is tied to a refund, swap, deferment or credit",
  MONEY_DECISION: "The session has an overpayment, credit or double-charge decision",
  OLD_WALLET_SETTLED: "Paid from an old e-wallet already settled",
};
const STATUS: Record<Run["status"], string> = { DELETED: "Duplicates deleted", NOTHING_TO_DELETE: "Nothing to delete", FAILED: "Failed — nothing changed" };
const when = (iso: string) => new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "Africa/Lagos" });
const n = (x: number) => Number(x).toLocaleString("en-NG");
const semesterWords = (s: number) => (s ? `Semester ${s}` : "Whole session");
const HEADERS = ["Group", "Record", "Matric number", "Session", "Level", "Semester", "Paid on", "Payment number", "Amount", "Why left whole"];

export function OldFeesDuplicateCleanup({ tick = 0 }: { tick?: number }) {
  const [data, setData] = useState<Cleanup | null>(null);
  const [busy, setBusy] = useState(true);

  useEffect(() => {
    let alive = true;
    void (async () => {
      const r = await fetch("/api/bff/api/v1/finance/legacy-fees/duplicate-cleanup?limit=500", { cache: "no-store" }).catch(() => null);
      const j = r ? await r.json().catch(() => null) : null;
      if (!alive) return;
      setBusy(false);
      if (!r || !r.ok) { notifyProblem((j ?? { status: r?.status ?? 0, title: r?.statusText || "The portal could not be reached" }) as Problem); return; }
      setData(j as Cleanup);
    })();
    return () => { alive = false; };
  }, [tick]);

  async function excel() {
    if (!data) return;
    const blob = await brandedXlsx("Old-portal school fees: duplicate groups left whole", HEADERS, data.leftWhole.map((r) => [
      r.group_key, r.reference, r.matric_no ?? "", r.session, r.level ?? "", semesterWords(r.semester), r.paid_on, r.payref, Number(r.amount), REASONS[r.reason] ?? r.reason,
    ]), { sheetName: "Left whole", serial: docSerial("LDR"), sub: `${n(data.now.groupsLeftWhole)} group${data.now.groupsLeftWhole === 1 ? "" : "s"} · ${n(data.now.recordsLeftWhole)} records` });
    downloadBlob(blob, "old-fees-duplicates-left-whole.xlsx");
  }

  const last = data?.runs[0] ?? null;
  const reasons = last ? (JSON.parse(last.skipped_by_reason || "{}") as Record<string, number>) : {};
  return (
    <Panel title="Duplicate school-fee records deleted on deployment" right="The same payment number, day, student, level, semester and session">
      <PBody>
        {busy ? <p className="sub2">Reading the cleanup…</p> : null}
        {data && !last ? (
          <Note kind="info" title="Not run here yet">The cleanup runs once, when the portal is deployed with it. Nothing has been deleted on this database.</Note>
        ) : null}
        {last ? (
          <>
            <Note kind={last.status === "FAILED" ? "bad" : last.status === "DELETED" ? "ok" : "info"}
              title={`${STATUS[last.status]} · ${when(last.finished_at)}`}>
              {last.status === "FAILED"
                ? <>The cleanup stopped and undid its work: no record was deleted. {last.error}</>
                : last.status === "DELETED"
                  ? <>{n(last.deleted)} duplicate record{last.deleted === 1 ? " was" : "s were"} deleted for good, one record of each group kept. A deleted record&rsquo;s printed receipt no longer opens; the kept record&rsquo;s does.</>
                  : <>No legacy school-fee record repeated another on all six fields.</>}
            </Note>
            <DTable cols={["Metric", "Result|num"]} noPrint
              rows={[
                ["Legacy school-fee records inspected", n(last.inspected)],
                ["Duplicate groups identified", n(last.groups_found)],
                ["Valid payment records retained", n(last.retained)],
                ["Duplicate records permanently deleted", n(last.deleted)],
                ["Amount the deleted records counted twice", money(Number(last.amount_deleted))],
                ["Students whose payments were put right", n(last.students)],
                ["Records skipped due to inconsistencies", `${n(last.records_skipped)} (${n(last.groups_skipped)} group${last.groups_skipped === 1 ? "" : "s"})`],
                ["Payment numbers sealed on the kept record", n(last.numbers_sealed)],
                ["Ledger journals moved / reversed", `${n(last.ledger_moved)} / ${n(last.ledger_released)}`],
                ["Financial reconciliation status", last.reconciliation === "PASSED" ? "Passed" : last.reconciliation === "FAILED" ? "Failed" : "Not run"],
                ["Referential integrity status", last.integrity === "PASSED" ? "Passed" : last.integrity === "FAILED" ? "Failed" : "Not run"],
                ["Cleanup execution status", last.status === "FAILED" ? "Failure" : "Success"],
              ].map(([a, b]) => [a, <span key="v" className="tnum">{b}</span>])}
            />
            {Object.keys(reasons).length ? (
              <p className="sub2 mt-1">Left whole: {Object.entries(reasons).map(([k, v]) => `${REASONS[k] ?? k} ${n(v)}`).join(" · ")}.</p>
            ) : null}
            <p className="sub2 mt-1">Run {last.run_ref} by {last.run_by} on {last.database_name}{data && data.runs.length > 1 ? ` · ${data.runs.length - 1} earlier run${data.runs.length === 2 ? "" : "s"}` : ""}.</p>
          </>
        ) : null}
        {data && data.now.deletable > 0 ? (
          <Note kind="bad" title="Duplicates on record again">
            {n(data.now.deletable)} record{data.now.deletable === 1 ? " repeats" : "s repeat"} another on all six fields now. Tell the Directorate of ICT: the next deployment&rsquo;s cleanup is the way they are removed.
          </Note>
        ) : null}
      </PBody>
      {data && data.leftWhole.length ? (
        <>
          <PBody>
            <div className="row row--inline">
              <span className="sub2">Groups left whole for the Bursary — each record stays until the conflict is settled</span>
              <Btn kind="ghost" onClick={() => void excel()}>Download Excel</Btn>
            </div>
          </PBody>
          <DTable cols={["Record", "Matric number", "Session", "Semester", "Paid on", "Payment number", "Amount|num", "Why left whole"]}
            rows={data.leftWhole.map((r) => [
              <span key="r" className="mono">{r.reference}</span>, r.matric_no ?? "—", r.session, semesterWords(r.semester), r.paid_on,
              <span key="p" className="mono">{r.payref}</span>, <span key="a" className="tnum">{money(Number(r.amount))}</span>, REASONS[r.reason] ?? r.reason,
            ])}
            texts={data.leftWhole.map((r) => `${r.reference} ${r.matric_no ?? ""} ${r.session} ${r.payref} ${r.reason}`)}
          />
        </>
      ) : null}
    </Panel>
  );
}
