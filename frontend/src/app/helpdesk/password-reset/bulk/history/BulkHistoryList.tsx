"use client";

/** Bulk reset history (V559): each bulk password reset — reference, date, who, the reason, how many were chosen, reset and failed,
 *  the status and the tickets — opening to each student's result. */
import Link from "next/link";
import { useQueryNav } from "@/lib/query-nav";
import { Btn, LinkBtn, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { STATUS, type BulkHistory } from "../BulkReset";

export interface HistoryFilters { from: string; to: string; status: string; q: string; page: number }

const when = (iso: string | null) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "Africa/Lagos" }) : "—");
const count = (n: number) => Number(n).toLocaleString("en-NG");

export function BulkHistoryList({ f, list }: { f: HistoryFilters; list: BulkHistory }) {
  const go = useQueryNav();
  const nav = (patch: Partial<HistoryFilters>) => {
    const next = { ...f, page: 1, ...patch };
    const qs = new URLSearchParams();
    for (const k of ["from", "to", "status", "q"] as const) if (next[k]) qs.set(k, next[k]);
    if (next.page > 1) qs.set("page", String(next.page));
    go(`/helpdesk/password-reset/bulk/history${qs.toString() ? `?${qs.toString()}` : ""}`);
  };
  const pages = Math.max(1, Math.ceil(list.total / (list.size || 50)));
  const HEAD = ["S/N", "Reference", "Date", "Performed by", "Office", "Reason", "Selected", "Reset", "Failed", "Status", "Tickets"];
  const sheet = list.rows.map((h, i) => [(list.page - 1) * list.size + i + 1, h.reference, when(h.created_at), h.performed_by, h.office, h.reason, h.total, h.succeeded, h.failed,
    STATUS[h.status]?.[0] ?? h.status, h.tickets ?? ""]);
  return (
    <>
      <PageHead title="Bulk reset history" eyebrow="ICT Support Desk"
        description={list.everyone ? "Every bulk password reset made at the desk, newest first." : "The bulk password resets you made, newest first."}
        actions={<><LinkBtn href="/helpdesk/password-reset/bulk">Bulk password reset</LinkBtn><LinkBtn href="/helpdesk/password-reset/history">Password reset history</LinkBtn></>} />
      <form className="filterbar" onSubmit={(e) => {
        e.preventDefault();
        const d = new FormData(e.currentTarget);
        nav({ from: String(d.get("from") ?? ""), to: String(d.get("to") ?? ""), status: String(d.get("status") ?? ""), q: String(d.get("q") ?? "").trim() });
      }}>
        <Field id="bh-from" label="From"><input id="bh-from" name="from" type="date" className="ctl" defaultValue={f.from} /></Field>
        <Field id="bh-to" label="To"><input id="bh-to" name="to" type="date" className="ctl" defaultValue={f.to} /></Field>
        <Field id="bh-status" label="Status">
          <select id="bh-status" name="status" className="ctl" defaultValue={f.status}>
            <option value="">Any</option>
            {Object.entries(STATUS).map(([k, [w]]) => <option key={k} value={k}>{w}</option>)}
          </select>
        </Field>
        <Field id="bh-q" label="Reference, officer or ticket number"><input id="bh-q" name="q" className="ctl" defaultValue={f.q} placeholder="BPR/2026/000001" /></Field>
        <button type="submit" className="btn btn--primary btn--sm" style={{ alignSelf: "flex-end" }}>Filter</button>
      </form>
      <Panel title={`${count(list.total)} bulk reset${list.total === 1 ? "" : "s"}${pages > 1 ? ` · page ${list.page} of ${pages}` : ""}`}
        right={<Btn kind="ghost" disabled={!list.rows.length} onClick={async () => downloadBlob(await brandedXlsx("Bulk Password Reset History", HEAD, sheet, { serial: docSerial("BPR") }), "bulk-password-reset-history.xlsx")}>Excel</Btn>}>
        {list.rows.length ? (
          <DTable pageSize={0} cols={["S/N|num", "Reference", "Date", "Performed by", "Reason", "Selected|num", "Reset|num", "Failed|num", "Status|mid", "Tickets"]} rows={list.rows.map((h, i) => [
            <span key="n" className="tnum sub2">{(list.page - 1) * list.size + i + 1}</span>,
            <Link key="r" href={`/helpdesk/password-reset/bulk/${h.id}`} className="lnk tnum">{h.reference}</Link>,
            <span key="d" className="tnum sub2">{when(h.created_at)}</span>,
            <span key="p">{h.performed_by}<div className="sub2">{h.office}</div></span>,
            <span key="w" className="sub2">{h.reason}</span>,
            <span key="t" className="tnum">{count(h.total)}</span>,
            <span key="s" className="tnum">{count(h.succeeded)}</span>,
            <span key="f" className="tnum">{count(h.failed)}</span>,
            <Pil key="st" kind={STATUS[h.status]?.[1] ?? "grey"}>{STATUS[h.status]?.[0] ?? h.status}</Pil>,
            <span key="k" className="sub2 tnum">{h.tickets ?? "—"}</span>,
          ])} />
        ) : <PBody><span className="sub2">No bulk password reset{f.from || f.to || f.status || f.q ? " matches" : " yet"}.</span></PBody>}
        {pages > 1 ? (
          <PBody>
            <div className="row row--inline" style={{ gap: 6 }}>
              <Btn kind="ghost" disabled={list.page <= 1} onClick={() => nav({ page: list.page - 1 })}>Previous</Btn>
              <Btn kind="ghost" disabled={list.page >= pages} onClick={() => nav({ page: list.page + 1 })}>Next</Btn>
            </div>
          </PBody>
        ) : null}
      </Panel>
    </>
  );
}
