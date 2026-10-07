"use client";
/** Payment Support (V346): the search. Any number the student holds — the portal's payment reference (the invoice the portal
 *  issues), the receipt, the gateway's or the transaction's reference, the matriculation, JAMB or application number, the
 *  student ID or the surname; the server searches within the agent's reach and pages. A row opens the diagnosis. */
import Link from "next/link";
import { useQueryNav } from "@/lib/query-nav";
import { LinkBtn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { PAY_WORD, type PaymentRow } from "@/lib/support";

const day = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }) : "—");
const naira = (v: unknown) => (v == null || v === "" ? "—" : `₦${Number(v).toLocaleString("en-NG", { minimumFractionDigits: 2 })}`);
const STATE: Record<string, ["ok" | "warn" | "grey", string]> = { CONFIRMED: ["ok", "Confirmed"], PENDING: ["warn", "Pending"], EXPIRED: ["grey", "Expired"] };

export function PaymentSearch({ q, state, ticket, page, list }: { q: string; state: string; ticket: string; page: number; list: { total: number; page: number; size: number; rows: PaymentRow[] } | null }) {
  const go = useQueryNav();
  function nav(patch: Record<string, string>) {
    const next: Record<string, string> = { q, state, ticket, page: "1", ...patch };
    const qs = new URLSearchParams();
    for (const [k, v] of Object.entries(next)) if (v && !(k === "page" && v === "1")) qs.set(k, v);
    go(`/helpdesk/payments${qs.toString() ? "?" + qs.toString() : ""}`);
  }
  const pages = list ? Math.max(1, Math.ceil(list.total / (list.size || 25))) : 1;
  const open = (ref: string) => `/helpdesk/payments/${encodeURIComponent(ref)}${ticket ? `?ticket=${encodeURIComponent(ticket)}` : ""}`;
  return (
    <>
      <PageHead title="Payment Support" eyebrow="ICT Support Desk"
        description="Find a student's payment by any number they hold and read what the gateway, the Bursary's ledger and the portal say about it. ICT Support verifies through the existing payment service and refreshes what a confirmed payment entitles — it never marks a payment paid, changes an amount or refunds."
        actions={<><LinkBtn href="/helpdesk/students">Student Support</LinkBtn><LinkBtn href="/helpdesk">Support Desk</LinkBtn></>} />
      <Panel title="Search">
        <PBody>
          <form className="row" style={{ flexWrap: "wrap", gap: "var(--s-3)", alignItems: "flex-end" }} onSubmit={(e) => { e.preventDefault(); const f = new FormData(e.currentTarget); nav({ q: String(f.get("q") ?? "").trim(), state: String(f.get("state") ?? "") }); }}>
            <Field id="ps-q" label="Payment, receipt, gateway or transaction reference — or the student" style={{ flex: "3 1 340px" }}>
              <input id="ps-q" name="q" className="ctl" type="search" defaultValue={q} placeholder="MOAUM-FEE-…, RCT-…, gateway or transaction reference, matric, JAMB or application number, surname" autoFocus />
            </Field>
            <Field id="ps-state" label="State" style={{ flex: "1 1 160px" }}>
              <select id="ps-state" name="state" className="ctl" defaultValue={state}><option value="">Any</option><option value="PENDING">Pending</option><option value="CONFIRMED">Confirmed</option><option value="EXPIRED">Expired</option></select>
            </Field>
            <button type="submit" className="btn btn--primary btn--sm">Search</button>
          </form>
        </PBody>
      </Panel>
      {!list ? (
        <Note kind="info" title="Start with any number the student holds">The portal&rsquo;s payment reference is the invoice it issues. A payment hanging at the gateway, a receipt that will not print, a payment the portal shows as unpaid — each starts here, and every act is written on the support ledger and the student&rsquo;s ticket.</Note>
      ) : (
        <Panel title={`${list.total.toLocaleString()} payment${list.total === 1 ? "" : "s"}`} right={list.total > list.size ? `Page ${page} of ${pages}` : undefined}>
          {list.rows.length ? (
            <DTable pageSize={0} cols={["Reference|mid", "Student", "Purpose", "Session|mid", "Amount|num", "Generated", "State|mid", "Gateway", "Receipt|mid", "|num"]} rows={list.rows.map((r) => [
              <Link key="r" className="lnk tnum b600" href={open(r.reference)}>{r.reference}</Link>,
              <span key="s">{r.student}<div className="sub2 tnum">{r.number ?? ""}{r.jamb_reg_no ? ` · JAMB ${r.jamb_reg_no}` : ""}</div></span>,
              <span key="p">{r.purpose}</span>, <span key="ss" className="tnum">{r.session}</span>, <span key="a" className="tnum">{naira(r.amount)}</span>,
              <span key="g" className="sub2">{day(r.generated_at)}</span>,
              <Pil key="st" kind={STATE[r.state]?.[0] ?? "grey"}>{STATE[r.state]?.[1] ?? r.state}</Pil>,
              <span key="gw" className="sub2">{r.gateway ? `${r.gateway} · ${PAY_WORD[r.gateway_outcome ?? ""]?.[0] ?? (r.gateway_outcome ?? "").toLowerCase().replace(/_/g, " ")}` : "—"}{r.gateway_ref ? <div className="tnum">{r.gateway_ref}</div> : null}</span>,
              <span key="rc" className="tnum">{r.receipt_no ?? "—"}</span>,
              <LinkBtn key="o" size="sm" kind="primary" href={open(r.reference)}>Investigate</LinkBtn>,
            ])} />
          ) : <PBody><div className="sub2">No payment within your reach carries that number. A payment made to an account the portal did not generate a reference for did not reach the University&rsquo;s ledger; ask the student for the bank evidence and escalate the ticket to the Bursary.</div></PBody>}
          {pages > 1 ? (
            <PBody><div className="row row--inline" style={{ gap: "var(--s-2)" }}>
              {page > 1 ? <button className="btn btn--ghost btn--sm" onClick={() => nav({ page: String(page - 1) })}>Previous</button> : null}
              {page < pages ? <button className="btn btn--ghost btn--sm" onClick={() => nav({ page: String(page + 1) })}>Next</button> : null}
            </div></PBody>
          ) : null}
        </Panel>
      )}
    </>
  );
}
