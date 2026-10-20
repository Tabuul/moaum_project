"use client";

/** V582: the password resets made from tickets, the latest first — the reader's own, or every one for a Head — each opened to its
 *  tickets and what became of each (the failed ones left open on the desk, linked); the login issue report and the reset
 *  operations report for a period, as Excel. */
import Link from "next/link";
import { useState } from "react";
import { notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { brandedXlsx, docSerial, downloadBlob } from "@/lib/exportbrand";
import { OP_STATUS, TICKET_RESULT, type Operation } from "@/lib/ticket-reset";

const BASE = "/api/bff/api/v1/helpdesk/tickets/password-reset";
const when = (iso: string | null | undefined) => (iso ? new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" }) : "—");

export interface OpRow { id: string; reference: string; status: string; total: number; succeeded: number; failed: number; created_at: string; completed_at: string | null; performed_by: string | null; tickets: number }

export function TicketResets({ ops }: { ops: OpRow[] }) {
  const [open, setOpen] = useState<Operation | null>(null);
  const [from, setFrom] = useState("");
  const [to, setTo] = useState("");

  async function show(id: string) {
    const r = await fetch(`${BASE}/operations/${id}`, { cache: "no-store" });
    const j = await r.json().catch(() => null);
    if (r.ok) setOpen(j as Operation); else notifyProblem(j ?? { status: r.status, title: r.statusText });
  }

  const period = () => { const q = new URLSearchParams(); if (from) q.set("from", from); if (to) q.set("to", to); return q.toString() ? `?${q}` : ""; };
  const span = `${from || "the beginning"} to ${to || "today"}`;

  async function loginReport() {
    const r = await fetch(`${BASE}/reports/login-issues${period()}`, { cache: "no-store" });
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
    const rows = j as Record<string, string | null>[];
    downloadBlob(await brandedXlsx("Login Issue Report", ["Ticket number", "Student", "Matric number", "Issue", "Category", "Created", "Assigned", "Ticket status", "Reset status", "Reset date", "Reset by", "Batch", "Resolved"],
      rows.map((x) => [x.number, x.requester_name, x.matric_no ?? x.requester_number ?? "", x.subject, x.category, when(x.created_at), x.assigned ?? "", x.status,
        x.reset_status ?? "Not reset", when(x.reset_at), x.reset_by ?? "", x.reset_reference ?? "", when(x.resolved_at)]),
      { serial: docSerial("LIR"), sub: `Login and password tickets raised from ${span}` }), `login-issue-report-${new Date().toISOString().slice(0, 10)}.xlsx`);
  }

  async function operationsReport() {
    const r = await fetch(`${BASE}/reports/operations${period()}`, { cache: "no-store" });
    const j = await r.json().catch(() => null);
    if (!r.ok) { notifyProblem(j ?? { status: r.status, title: r.statusText }); return; }
    const rows = j as Record<string, string | null>[];
    downloadBlob(await brandedXlsx("Password Reset Operations Report", ["Batch", "Ticket number", "Student", "Matric number", "Reset type", "Result", "Reason", "Actor", "Date"],
      rows.map((x) => [x.reference, x.number, x.full_name ?? "", x.matric_no ?? "", x.reset_type, TICKET_RESULT[x.result as keyof typeof TICKET_RESULT]?.[0] ?? x.result, x.reason ?? "", x.actor ?? "", when(x.at)]),
      { serial: docSerial("PRO"), sub: `Password resets from tickets made from ${span}` }), `password-reset-operations-${new Date().toISOString().slice(0, 10)}.xlsx`);
  }

  return (
    <>
      <Note kind="info" title="Password resets are made from the tickets on the queue">
        On the ICT support desk, choose Login and password issues, tick the tickets and press Reset selected passwords. Each student is reset once however many
        tickets they raised; their tickets are resolved with the reset, and a ticket whose student could not be reset stays open with the reason.
      </Note>
      <Tiles items={[
        ["Resets from tickets", String(ops.length), null, "Operations listed below"],
        ["Students reset", String(ops.reduce((n, o) => n + Number(o.succeeded), 0)), null, "Across them"],
        ["Not reset", String(ops.reduce((n, o) => n + Number(o.failed), 0)), ops.some((o) => o.failed) ? "var(--red-ink)" : null, "Their tickets stay open on the desk"],
        ["Tickets", String(ops.reduce((n, o) => n + Number(o.tickets), 0)), null, "Taken by the operations"],
      ]} />
      <Panel title="Reports" right={<LinkBtn href="/helpdesk?issue=login">Login issues on the queue</LinkBtn>}>
        <PBody>
          <div className="row row--tight" style={{ gap: 8, flexWrap: "wrap", alignItems: "flex-end" }}>
            <Field id="tr-from" label="From"><input id="tr-from" type="date" className="ctl" value={from} onChange={(e) => setFrom(e.target.value)} /></Field>
            <Field id="tr-to" label="To"><input id="tr-to" type="date" className="ctl" value={to} onChange={(e) => setTo(e.target.value)} /></Field>
            <Btn kind="ghost" busyLabel="Preparing Excel..." onClick={() => loginReport()}>Login issue report</Btn>
            <Btn kind="ghost" busyLabel="Preparing Excel..." onClick={() => operationsReport()}>Password reset operations report</Btn>
          </div>
        </PBody>
      </Panel>
      <Panel title="Password resets from tickets" right={`${ops.length} · the latest first`}>
        {ops.length ? (
          <DTable cols={["S/N|num", "Batch", "Status", "Tickets|num", "Students reset|num", "Not reset|num", "By", "Started", "|num"]} rows={ops.map((o, i) => [
            <span key="n" className="tnum sub2">{i + 1}</span>,
            <span key="r" className="tnum b600">{o.reference}</span>,
            <Pil key="s" kind={OP_STATUS[o.status]?.[1] ?? "grey"}>{OP_STATUS[o.status]?.[0] ?? o.status}</Pil>,
            <span key="t" className="tnum">{o.tickets}</span>,
            <span key="ok" className="tnum">{o.succeeded}</span>,
            <span key="f" className={`tnum${o.failed ? " ink-red b600" : ""}`}>{o.failed}</span>,
            <span key="b" className="sub2">{o.performed_by ?? "—"}</span>,
            <span key="c" className="sub2 tnum">{when(o.created_at)}</span>,
            <Btn key="o" kind="ghost" size="sm" onClick={() => show(o.id)}>Open</Btn>,
          ])} texts={ops.map((o) => `${o.reference} ${o.performed_by ?? ""}`)} />
        ) : <PBody><div className="sub2">No password has been reset from tickets yet.</div></PBody>}
      </Panel>
      {open ? (
        <Modal wide title={`${open.reference} · ${OP_STATUS[open.status]?.[0] ?? open.status}`} sub={`${open.ticketCount} tickets · ${open.students} students · ${open.consolidated} duplicate tickets consolidated · by ${open.performed_by ?? "—"}`}
          onClose={() => setOpen(null)} foot={<Btn kind="primary" onClick={() => setOpen(null)}>Close</Btn>}>
          <DTable cols={["S/N|num", "Ticket", "Student", "Matric number", "Issue", "Result", "Reason", "Processed"]} rows={open.tickets.map((t, i) => [
            <span key="n" className="tnum sub2">{i + 1}</span>,
            <Link key="t" className="lnk tnum" href={`/helpdesk/tickets/${t.ticket_id}`}>{t.number}</Link>,
            <span key="s">{t.full_name ?? "—"}</span>,
            <span key="m" className="tnum">{t.matric_no ?? "—"}</span>,
            <span key="i" className="sub2">{t.subject}</span>,
            <Pil key="r" kind={TICKET_RESULT[t.status][1]}>{TICKET_RESULT[t.status][0]}</Pil>,
            <span key="w" className="sub2">{t.reason ?? ""}</span>,
            <span key="p" className="sub2 tnum">{when(t.processed_at)}</span>,
          ])} texts={open.tickets.map((t) => `${t.number} ${t.full_name ?? ""} ${t.matric_no ?? ""}`)} />
        </Modal>
      ) : null}
    </>
  );
}
