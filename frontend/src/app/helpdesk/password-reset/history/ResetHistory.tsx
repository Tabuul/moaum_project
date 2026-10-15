"use client";

/** Password Reset History (V485): every password reset and account unlock ICT Support made on a student — who, which student, the
 *  method, the reason, the ticket, when and the result — from the support ledger, within the reader's reach. A password, a hash or
 *  anything that would let one be guessed is never on it, and there is nothing here to download. */
import Link from "next/link";
import { useQueryNav } from "@/lib/query-nav";
import { LinkBtn, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { RESULT_WORD } from "@/lib/support";
import { METHOD_WORD } from "@/lib/password-reset";
import type { AuditList } from "@/app/helpdesk/audit/SupportAudit";

const when = (iso: string) => new Date(iso).toLocaleString("en-GB", { day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit" });

export function ResetHistory({ list, page, from, to }: { list: AuditList; page: number; from: string; to: string }) {
  const go = useQueryNav();
  const nav = (patch: Record<string, string>) => {
    const qs = new URLSearchParams();
    for (const [k, v] of Object.entries({ from, to, page: "1", ...patch })) if (v && !(k === "page" && v === "1")) qs.set(k, v);
    go(`/helpdesk/password-reset/history${qs.toString() ? "?" + qs.toString() : ""}`);
  };
  const pages = Math.max(1, Math.ceil(list.total / (list.size || 50)));
  return (
    <>
      <PageHead title="Password reset history" eyebrow="ICT Support Desk"
        description="Every student password reset and account unlock made at the desk, newest first. Passwords are never recorded or shown."
        actions={<><LinkBtn href="/helpdesk/password-reset">Student password reset</LinkBtn><LinkBtn href="/helpdesk/audit?module=AUTHENTICATION">Support action history</LinkBtn></>} />
      <form className="filterbar" onSubmit={(e) => { e.preventDefault(); const f = new FormData(e.currentTarget); nav({ from: String(f.get("from") ?? ""), to: String(f.get("to") ?? "") }); }}>
        <Field id="rh-from" label="From"><input id="rh-from" name="from" type="date" className="ctl" defaultValue={from} /></Field>
        <Field id="rh-to" label="To"><input id="rh-to" name="to" type="date" className="ctl" defaultValue={to} /></Field>
        <button type="submit" className="btn btn--primary btn--sm" style={{ alignSelf: "flex-end" }}>Filter</button>
      </form>
      <Panel title={`${list.total.toLocaleString("en-GB")} reset${list.total === 1 ? "" : "s"} and unlock${list.total === 1 ? "" : "s"}`} right={pages > 1 ? `Page ${page} of ${pages}` : undefined}>
        {list.rows.length ? (
          <DTable pageSize={0} cols={["S/N|num", "Student", "Matriculation number", "Reset by", "Role", "Action", "Reason", "Ticket|mid", "Date/time", "Result|mid"]}
            rows={list.rows.map((r, i) => [
              <span key="sn" className="tnum sub2">{(page - 1) * (list.size || 50) + i + 1}</span>,
              r.student_id ? <Link key="s" className="lnk" href={`/helpdesk/students/${r.student_id}?tab=history`}>{r.student}</Link> : <span key="s">{r.student}<div className="sub2">JUPEB</div></span>,
              <span key="m" className="tnum">{r.number ?? "—"}</span>,
              <span key="a">{r.agent}</span>,
              <span key="o" className="sub2">{r.agent_office}</span>,
              <span key="k">{r.action === "ACCOUNT_UNLOCKED" ? <b>Account unlocked</b> : <><b>Password reset</b><div className="sub2">{METHOD_WORD[r.method ?? ""] ?? r.method ?? ""}</div></>}</span>,
              <span key="r" className="sub2">{r.reason}</span>,
              r.ticket_id ? <Link key="t" href={`/helpdesk/tickets/${r.ticket_id}`} className="lnk tnum">{r.ticket_number}</Link> : <span key="t" className="sub2">—</span>,
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
