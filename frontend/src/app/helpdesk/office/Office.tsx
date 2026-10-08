"use client";
/** The office's desk (V328): what the support desk has put to this office for a decision, oldest first, and what the office
 *  answered before. Each row opens the ticket, where the office reads the agent's question and answers it. */
import Link from "next/link";
import { LinkBtn, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { PriorityPil, StatusPil, when, type TicketRow } from "@/lib/helpdesk";
import type { OfficeData } from "./page";

export function Office({ data }: { data: OfficeData }) {
  const offices = data.offices.map((o) => o.label).join(", ") || "your office";
  const overdue = data.waiting.filter((t) => t.overdue).length;
  const row = (t: TicketRow, waiting: boolean) => [
    <span key="n"><Link className="lnk tnum b600" href={`/helpdesk/office/${t.id}`}>{t.number}</Link>{t.overdue ? <div><Pil kind="bad">Overdue</Pil></div> : null}</span>,
    <span key="r"><strong>{t.requester_name}</strong><div className="sub2 tnum">{t.requester_number ?? t.requester_email ?? ""} · {t.requester_kind === "STUDENT" ? "Student" : "Staff"}</div></span>,
    <span key="c" className="sub2">{t.category}{t.queue ? <div>{t.queue}</div> : null}</span>,
    <span key="s">{t.subject}</span>,
    <PriorityPil key="p" priority={t.priority} />,
    <StatusPil key="st" status={t.status} />,
    <span key="a" className="sub2">{t.agent ?? "No agent"}</span>,
    <span key="w" className="tnum sub2">{waiting ? when(t.waiting_since) : when(t.updated_at)}</span>,
    <LinkBtn key="o" href={`/helpdesk/office/${t.id}`} kind={waiting ? "primary" : "ghost"} size="sm">{waiting ? "Decide" : "Open"}</LinkBtn>,
  ];
  return (
    <>
      <PageHead title="Support escalations" description={`Tickets the ICT Support Desk has referred to ${offices} for a decision support cannot take. Your answer goes to the agent on the ticket; the ticket waits until it comes.`}
        actions={<LinkBtn href="/tickets">My Own Tickets</LinkBtn>} />
      <Tiles items={[
        ["Awaiting your decision", String(data.waiting.length), data.waiting.length ? "var(--amber-ink)" : null, "Referred by the support desk, oldest first"],
        ["Overdue", String(overdue), overdue ? "var(--red-ink)" : null, "Past the ticket's SLA while it waits"],
        ["Answered by you", String(data.answered.length), null, "Back with the desk"],
        ["Your offices", String(data.offices.length), null, offices],
      ]} />
      <Panel title="Awaiting your decision" right={data.waiting.length ? `${data.waiting.length} ticket${data.waiting.length === 1 ? "" : "s"}` : "Nothing waits on you"}>
        {data.waiting.length ? (
          <DTable pageSize={0} cols={["Ticket", "Requester", "Category", "Subject", "Priority|mid", "Status|mid", "Agent", "Waiting since|mid", "|num"]} rows={data.waiting.map((t) => row(t, true))} />
        ) : <PBody><div className="sub2">When an agent cannot settle a ticket without your office&rsquo;s decision — a fee, a result, a registration, a refund — they escalate it here. It lists until you answer.</div></PBody>}
      </Panel>
      <Panel title="Answered by you" right={data.answered.length ? "The last fifty" : "None yet"}>
        {data.answered.length ? (
          <DTable pageSize={0} cols={["Ticket", "Requester", "Category", "Subject", "Priority|mid", "Status|mid", "Agent", "Updated|mid", "|num"]} rows={data.answered.map((t) => row(t, false))} />
        ) : <PBody><div className="sub2">Tickets you have answered stay readable here.</div></PBody>}
      </Panel>
    </>
  );
}
