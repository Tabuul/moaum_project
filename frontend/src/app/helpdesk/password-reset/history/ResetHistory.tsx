"use client";

/** Password Reset History (V485): every password reset and account unlock ICT Support made on a student — who, which student, the
 *  method, the reason, the ticket, when and the result — from the support ledger, within the reader's reach. A password, a hash or
 *  anything that would let one be guessed is never on it, nor on its Excel or PDF (V500: S/N first, display only). */
import Link from "next/link";
import { useQueryNav } from "@/lib/query-nav";
import { Btn, LinkBtn, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { notifyProblem } from "@/components/proto/Toast";
import { brandedPrint, brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { RESULT_WORD } from "@/lib/support";
import { METHOD_WORD } from "@/lib/password-reset";
import type { AuditList } from "@/app/helpdesk/audit/SupportAudit";
import type { ResetsByAgent as Counts } from "@/lib/password-reset";
import { ResetsByAgent } from "./ResetsByAgent";

const when = (iso: string) => new Date(iso).toLocaleString("en-GB", { day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" });

const KINDS: [string, string][] = [["", "Every reset"], ["SINGLE", "Single resets"], ["BULK", "In bulk resets"], ["LINK", "Reset links"]];

export function ResetHistory({ list, page, from, to, kind = "", byAgent }: { list: AuditList; page: number; from: string; to: string; kind?: string; byAgent?: Counts | null }) {
  const go = useQueryNav();
  const nav = (patch: Record<string, string>) => {
    const qs = new URLSearchParams();
    for (const [k, v] of Object.entries({ from, to, kind, page: "1", ...patch })) if (v && !(k === "page" && v === "1")) qs.set(k, v);
    go(`/helpdesk/password-reset/history${qs.toString() ? "?" + qs.toString() : ""}`);
  };
  const pages = Math.max(1, Math.ceil(list.total / (list.size || 50)));
  // V500: the export — the same rows the reader reads here, never a password or a hash; a reset reads RESET COMPLETED
  const HEAD = ["S/N", "Student", "Matric No", "Username", "Action", "Reset By", "Role", "Reason", "Ticket", "Bulk reset", "Date", "Result"];
  const line = (r: AuditList["rows"][number], i: number) => [i + 1, r.student, r.number ?? "", r.number ?? "",
    r.action === "ACCOUNT_UNLOCKED" ? "ACCOUNT UNLOCKED" : r.method === "RESET_LINK" ? "RESET LINK SENT" : "RESET COMPLETED", r.agent, r.agent_office, r.reason,
    r.ticket_number ?? "", r.bulk_reference ?? "", when(r.at), RESULT_WORD[r.result]?.[0] ?? r.result];
  async function all() {
    const p = new URLSearchParams({ module: "AUTHENTICATION", export: "true", size: "5000" });
    if (from) p.set("from", from);
    if (to) p.set("to", to);
    if (kind) p.set("kind", kind);
    const r = await fetch(`/api/bff/api/v1/helpdesk/support/actions?${p.toString()}`, { cache: "no-store" });
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem(j ?? { status: r.status, title: "The history could not be read just now." }); return null; }
    return (j as AuditList).rows;
  }
  const sub = [KINDS.find(([k]) => k === kind && k)?.[1] ?? null, from ? `from ${from}` : null, to ? `to ${to}` : null].filter(Boolean).join(" · ");
  return (
    <>
      <PageHead title="Password reset history" eyebrow="ICT Support Desk"
        description="Every student password reset and account unlock made at the desk, newest first. Passwords are never recorded or shown."
        actions={<><LinkBtn href="/helpdesk/password-reset">Student password reset</LinkBtn><LinkBtn href="/helpdesk/password-reset/bulk/history">Bulk reset history</LinkBtn><LinkBtn href="/helpdesk/audit?module=AUTHENTICATION">Support action history</LinkBtn></>} />
      {/* V528: the Head's view of each agent's resets (the Head, the Director of ICT, admin, super) */}
      {byAgent ? <ResetsByAgent counts={byAgent} /> : null}
      <form className="filterbar" onSubmit={(e) => { e.preventDefault(); const f = new FormData(e.currentTarget); nav({ from: String(f.get("from") ?? ""), to: String(f.get("to") ?? ""), kind: String(f.get("kind") ?? "") }); }}>
        <Field id="rh-kind" label="Kind">
          <select id="rh-kind" name="kind" className="ctl" defaultValue={kind}>
            {KINDS.map(([k, w]) => <option key={k} value={k}>{w}</option>)}
          </select>
        </Field>
        <Field id="rh-from" label="From"><input id="rh-from" name="from" type="date" className="ctl" defaultValue={from} /></Field>
        <Field id="rh-to" label="To"><input id="rh-to" name="to" type="date" className="ctl" defaultValue={to} /></Field>
        <button type="submit" className="btn btn--primary btn--sm" style={{ alignSelf: "flex-end" }}>Filter</button>
      </form>
      <Panel title={`${list.total.toLocaleString("en-GB")} reset${list.total === 1 ? "" : "s"} and unlock${list.total === 1 ? "" : "s"}${pages > 1 ? ` · page ${page} of ${pages}` : ""}`}
        right={<div className="row row--inline" style={{ gap: 6 }}>
          <Btn kind="ghost" size="sm" disabled={!list.total} busyLabel="Preparing Excel..." onClick={async () => {
            const rows = await all();
            if (rows) downloadBlob(await brandedXlsx("Password Reset History", HEAD, rows.map(line), { sub, serial: docSerial("PWR") }), "password-reset-history.xlsx");
          }}>Excel</Btn>
          <Btn kind="ghost" size="sm" disabled={!list.total} busyLabel="Preparing PDF..." onClick={async () => {
            const rows = await all();
            if (rows) brandedPrint("Password Reset History", sub, HEAD, rows.map(line), docSerial("PWR"));
          }}>PDF</Btn>
        </div>}>
        {list.rows.length ? (
          <DTable pageSize={0} cols={["S/N|num", "Student", "Matriculation number", "Reset by", "Role", "Action", "Reason", "Ticket|mid", "Bulk reset", "Date/time", "Result|mid"]}
            rows={list.rows.map((r, i) => [
              <span key="sn" className="tnum sub2">{(page - 1) * (list.size || 50) + i + 1}</span>,
              r.student_id ? <Link key="s" className="lnk" href={`/helpdesk/students/${r.student_id}?tab=history`}>{r.student}</Link> : <span key="s">{r.student}<div className="sub2">JUPEB</div></span>,
              <span key="m" className="tnum">{r.number ?? "—"}</span>,
              <span key="a">{r.agent}</span>,
              <span key="o" className="sub2">{r.agent_office}</span>,
              <span key="k">{r.action === "ACCOUNT_UNLOCKED" ? <b>Account unlocked</b> : <><b>Password reset</b><div className="sub2">{METHOD_WORD[r.method ?? ""] ?? r.method ?? ""}</div></>}</span>,
              <span key="r" className="sub2">{r.reason}</span>,
              r.ticket_id ? <Link key="t" href={`/helpdesk/tickets/${r.ticket_id}`} className="lnk tnum">{r.ticket_number}</Link> : <span key="t" className="sub2">—</span>,
              r.bulk_id ? <Link key="b" href={`/helpdesk/password-reset/bulk/${r.bulk_id}`} className="lnk tnum">{r.bulk_reference}</Link> : <span key="b" className="sub2">—</span>,
              <span key="w" className="sub2 tnum">{when(r.at)}</span>,
              <Pil key="res" kind={RESULT_WORD[r.result]?.[1] ?? "grey"}>{RESULT_WORD[r.result]?.[0] ?? r.result}</Pil>,
            ])} />
        ) : <PBody><div className="sub2">No password reset matches.</div></PBody>}
        {pages > 1 ? (
          <PBody><div className="row row--inline" style={{ gap: "var(--s-2)" }}>
            {page > 1 ? <button className="btn btn--ghost btn--sm" onClick={() => nav({ page: String(page - 1) })}>Previous</button> : null}
            {page < pages ? <button className="btn btn--ghost btn--sm" onClick={() => nav({ page: String(page + 1) })}>Next</button> : null}
          </div></PBody>
        ) : null}
      </Panel>
    </>
  );
}
