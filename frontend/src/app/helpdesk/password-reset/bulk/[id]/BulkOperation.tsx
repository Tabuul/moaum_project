"use client";

/** One bulk password reset (V559): the operation — reference, who made it, the reason, when, the counts — and each student's
 *  result with the reason a student was not reset; read again every two seconds while it runs. No password is on it, nor on its
 *  Excel or PDF. */
import { useEffect, useState } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { Btn, LinkBtn, PageHead, Panel, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { notifyProblem } from "@/components/proto/Toast";
import { reasonHeader } from "@/lib/reason";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { STATUS, type Operation, type OpItem } from "../BulkReset";

const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "Africa/Lagos" }) : "—");
const count = (n: number) => Number(n).toLocaleString("en-NG");
const RESULT: Record<string, [string, "grey" | "ok" | "bad" | "info"]> = {
  PENDING: ["Waiting", "grey"], RESET: ["Reset", "ok"], ALREADY_RESET: ["Already reset", "info"], FAILED: ["Failed", "bad"],
};

export function BulkOperation({ op }: { op: Operation }) {
  const router = useRouter();
  const [show, setShow] = useState<"ALL" | "OK" | "FAILED">("ALL");
  const running = op.status === "PENDING" || op.status === "PROCESSING";

  useEffect(() => {
    if (!running) return;
    const t = setInterval(() => router.refresh(), 2000);
    return () => clearInterval(t);
  }, [running, router]);

  const items: OpItem[] = op.items ?? [];
  const shown = items.filter((i) => show === "ALL" || (show === "FAILED" ? i.status === "FAILED" : i.status === "RESET" || i.status === "ALREADY_RESET"));
  const HEAD = ["S/N", "Student", "Matriculation number", "Programme", "Faculty", "Level", "Ticket", "Result", "Reason", "Processed"];
  const line = (i: OpItem, n: number) => [n + 1, i.name, i.number ?? "", i.programme ?? "", i.faculty ?? "", i.level ?? "", i.ticket_number ?? "",
    RESULT[i.status]?.[0] ?? i.status, i.failure_words ?? "", when(i.processed_at)];
  const meta: [string, string][] = [["Reference", op.reference], ["Performed by", op.performed_by], ["Reason", op.reason], ["Date", when(op.created_at)],
    ["Selected", String(op.total)], ["Reset", String(op.succeeded)], ["Failed", String(op.failed)], ["Status", STATUS[op.status]?.[0] ?? op.status]];

  async function cancel() {
    const r = await fetch(`/api/bff/api/v1/helpdesk/support/password-reset/bulk/${op.id}/cancel`, {
      method: "POST", headers: { "X-Reason": reasonHeader(`Bulk password reset ${op.reference} cancelled`) },
    });
    if (!r.ok) notifyProblem((await r.json().catch(() => null)) ?? { status: r.status, title: "The reset could not be cancelled just now." });
    router.refresh();
  }

  return (
    <>
      <PageHead title={op.reference} eyebrow="Bulk password reset"
        description={<>By {op.performed_by}{op.office ? ` (${op.office})` : ""} on {when(op.created_at)}{op.completed_at ? `, finished ${when(op.completed_at)}` : ""}. Reason: {op.reason}</>}
        actions={<>
          {running ? <Btn kind="ghost" onClick={cancel}>Cancel the rest</Btn> : null}
          <LinkBtn href="/helpdesk/password-reset/bulk/history">Bulk reset history</LinkBtn>
          <LinkBtn href="/helpdesk/password-reset/bulk">Bulk password reset</LinkBtn>
        </>} />
      <Tiles cls="grid--4" items={[
        ["Status", <Pil key="s" kind={STATUS[op.status]?.[1] ?? "grey"}>{STATUS[op.status]?.[0] ?? op.status}</Pil>, null, running ? `${count(op.processed)} of ${count(op.total)} processed` : "final"],
        ["Selected", count(op.total), null, "students"],
        ["Successfully reset", count(op.succeeded), op.succeeded ? "var(--green-ink)" : null, "must change at the next sign-in"],
        ["Failed", count(op.failed), op.failed ? "var(--red-ink)" : null, "not reset, with the reason"],
      ]} />
      <Panel title="Students" right={<div className="row row--inline" style={{ gap: 6 }}>
        {(["ALL", "OK", "FAILED"] as const).map((k) => (
          <Btn key={k} kind={show === k ? "secondary" : "ghost"} onClick={() => setShow(k)}>{k === "ALL" ? `All (${count(items.length)})` : k === "OK" ? "Reset" : "Failed"}</Btn>
        ))}
        <Btn kind="ghost" disabled={!items.length} onClick={async () => downloadBlob(await brandedXlsx("Bulk Password Reset", HEAD, items.map(line), { sheetName: "Bulk reset", serial: docSerial("BPR"), sub: op.reference, meta }), `${op.reference.replace(/\//g, "-")}.xlsx`)}>Excel</Btn>
        <Btn kind="ghost" disabled={!items.length} onClick={() => brandedPrint("Bulk Password Reset", op.reference, HEAD, items.map(line), docSerial("BPR"), { meta, orientation: "landscape" })}>PDF</Btn>
      </div>}>
        <DTable pageSize={25} texts={shown.map((i) => `${i.name} ${i.number ?? ""} ${i.programme ?? ""} ${i.ticket_number ?? ""}`)}
          cols={["S/N|num", "Student", "Matriculation number", "Programme", "Level|num", "Ticket", "Result|mid", "Reason", "Processed"]}
          rows={shown.map((i, n) => [
            <span key="n" className="tnum sub2">{n + 1}</span>,
            <Link key="s" className="lnk" href={`/helpdesk/students/${i.student_id}?tab=history`}>{i.name}</Link>,
            <span key="m" className="tnum">{i.number ?? "—"}</span>,
            <span key="p" className="sub2">{i.programme ?? "—"}<div>{i.faculty ?? ""}</div></span>,
            <span key="l" className="tnum">{i.level ?? "—"}</span>,
            <span key="t" className="tnum sub2">{i.ticket_number ?? "—"}</span>,
            <Pil key="r" kind={RESULT[i.status]?.[1] ?? "grey"}>{RESULT[i.status]?.[0] ?? i.status}</Pil>,
            <span key="w" className="sub2">{i.failure_words ?? (i.status === "ALREADY_RESET" ? "Reset moments before; not reset twice" : "")}</span>,
            <span key="d" className="sub2 tnum">{when(i.processed_at)}</span>,
          ])} />
        {op.missing ? <div className="sub2" style={{ padding: "8px 16px" }}>{op.missing} chosen record{op.missing === 1 ? " was" : "s were"} not found, and counted as failed.</div> : null}
      </Panel>
    </>
  );
}
