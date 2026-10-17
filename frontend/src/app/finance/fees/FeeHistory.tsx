"use client";

/**
 * Fee history (V520): every change to the session's fee lines — added, changed, ended — from the audit trail, with who, when, why and
 * the amount before and after. Nothing is ever rewritten: an earlier amount stays on record, and a payment keeps the amount it was
 * made against. Read when opened, so the page does not wait for it.
 */
import { useState } from "react";
import { Btn, Panel, PBody } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { notifyProblem } from "@/components/proto/Toast";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";

interface FeeChange {
  at: string; action: string; office: string; reason: string | null; by_name: string | null; item: string | null; amount_before: number | null; amount_after: number | null;
  level: string | null; programme_code: string | null; faculty_code: string | null; entry_mode: string | null; semester: string | null; ended: boolean;
}

const naira = (n: number | null) => (n == null ? "—" : `₦${Number(n).toLocaleString("en-GB", { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`);
const when = (iso: string) => new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" });
const what = (c: FeeChange) => (c.action === "INSERT" ? "Added" : c.ended ? "Ended" : c.action === "DELETE" ? "Removed" : "Changed");
const scopeOf = (c: FeeChange) => [c.level ? `${c.level} Level` : null, c.programme_code, c.faculty_code, c.entry_mode, c.semester ? `semester ${c.semester}` : null].filter(Boolean).join(" · ") || "Every student";

export function FeeHistory({ session }: { session: string }) {
  const [rows, setRows] = useState<FeeChange[] | null>(null);

  async function open() {
    const r = await fetch(`/api/bff/api/v1/finance/sessions/${session}/schedule/history`, { cache: "no-store" });
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
    setRows(j as FeeChange[]);
  }

  async function excel() {
    if (!rows) return;
    const head = ["S/N", "When", "Change", "Item", "For", "Amount before", "Amount after", "By", "Office", "Reason"];
    downloadBlob(await brandedXlsx("Fee History", head, rows.map((c, i) => [i + 1, when(c.at), what(c), c.item ?? "", scopeOf(c), c.amount_before ?? "", c.amount_after ?? "",
      c.by_name ?? "", c.office, c.reason ?? ""]), { sheetName: "Fee history", serial: docSerial("FEH"), sub: session }), `fee-history-${session.replace("/", "-")}.xlsx`);
  }

  return (
    <Panel title={`Fee history, ${session}`} right={rows ? `${rows.length} change${rows.length === 1 ? "" : "s"}` : undefined}>
      <PBody>
        <div className="row row--between" style={{ flexWrap: "wrap", gap: 8 }}>
          <span className="sub2">Every fee line added, changed or ended for the session, with who, when and why. Nothing is overwritten: the earlier amount stays on record.</span>
          <span className="row row--inline row--tight">
            {rows ? <Btn kind="ghost" size="sm" disabled={!rows.length} busyLabel="Preparing Excel…" onClick={() => excel()}>Excel</Btn> : null}
            <Btn kind="secondary" size="sm" busyLabel="Reading…" onClick={() => open()}>{rows ? "Read again" : "Show the history"}</Btn>
          </span>
        </div>
      </PBody>
      {rows && rows.length ? (
        <DTable pageSize={25} cols={["S/N|num", "When|mid", "Change", "Item", "For", "Before|num", "After|num", "By", "Reason"]}
          rows={rows.map((c, i) => [
            <span key="n" className="tnum sub2">{i + 1}</span>, <span key="w" className="tnum sub2">{when(c.at)}</span>, <span key="c">{what(c)}</span>,
            <span key="i">{c.item ?? "—"}</span>, <span key="s" className="sub2">{scopeOf(c)}</span>,
            <span key="b" className="tnum">{naira(c.amount_before)}</span>, <span key="a" className="tnum">{naira(c.amount_after)}</span>,
            <span key="p" className="sub2">{c.by_name ?? c.office}</span>, <span key="r" className="sub2">{c.reason ?? "—"}</span>,
          ])} />
      ) : rows ? <PBody><div className="sub2">No change recorded for {session}.</div></PBody> : null}
    </Panel>
  );
}
