"use client";

/** V582: a ticket's password reset history — from tickets on the queue, in a student bulk reset, or the single reset on the ticket —
 *  who, when, which operation, what became of it and whether the change is forced; never a password. Nothing is shown for a ticket
 *  whose student was never reset from it. */
import { useEffect, useState } from "react";
import { Panel, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

interface ResetRow { at: string; kind: "FROM_TICKETS" | "BULK" | "SINGLE"; reference: string | null; by_name: string | null; result: string; words: string | null; force_change: boolean }

const KIND: Record<ResetRow["kind"], string> = { FROM_TICKETS: "From tickets on the queue", BULK: "Student bulk reset", SINGLE: "Single reset on the ticket" };
const RESULT: Record<string, [string, "ok" | "info" | "warn" | "bad" | "grey"]> = {
  RESET: ["Reset", "ok"], FAILED: ["Not reset", "bad"], PENDING: ["Waiting", "info"], AWAITING_APPROVAL: ["Waiting for approval", "warn"],
};
const when = (iso: string | null) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");

export function ResetHistory({ ticketId }: { ticketId: string }) {
  const [rows, setRows] = useState<ResetRow[] | null>(null);
  useEffect(() => {
    let live = true;
    (async () => {
      const r = await fetch(`/api/bff/api/v1/helpdesk/tickets/password-reset/history/${ticketId}`, { cache: "no-store" });
      const j = r.ok ? ((await r.json()) as ResetRow[]) : [];
      if (live) setRows(j);
    })();
    return () => { live = false; };
  }, [ticketId]);
  if (!rows || !rows.length) return null;
  return (
    <Panel title="Password reset history" right={`${rows.length} reset${rows.length === 1 ? "" : "s"}`}>
      <DTable cols={["Reset date", "Reset by", "Reset type", "Batch", "Result", "Force password change|mid", "What happened"]} rows={rows.map((h, i) => [
        <span key={`a${i}`} className="tnum sub2">{when(h.at)}</span>,
        <span key="b">{h.by_name ?? "—"}</span>,
        <span key="k" className="sub2">{KIND[h.kind] ?? h.kind}</span>,
        <span key="r" className="tnum">{h.reference ?? "—"}</span>,
        <Pil key="s" kind={RESULT[h.result]?.[1] ?? "grey"}>{RESULT[h.result]?.[0] ?? h.result}</Pil>,
        <span key="f">{h.force_change ? "Yes" : "No"}</span>,
        <span key="w" className="sub2">{h.words ?? ""}</span>,
      ])} />
    </Panel>
  );
}
