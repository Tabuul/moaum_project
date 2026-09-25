import Link from "next/link";
import { api } from "@/lib/api";
import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { LinkBtn, Note, PageHead, Panel, PBody, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { PriorityPil, StatusPil, when, type TicketRow } from "@/lib/helpdesk";
import { requester } from "./who";

export const dynamic = "force-dynamic";

/** My support tickets — every ticket you have raised with the Directorate of ICT, and the door to a new one */
export default async function MyTicketsPage() {
  const { me, route } = await requester();
  const r = await api<TicketRow[]>("/api/v1/helpdesk/my/tickets");
  const rows = r.ok ? r.data : [];
  const open = rows.filter((t) => t.status !== "CLOSED");
  const resolved = rows.filter((t) => t.status === "RESOLVED");
  return (
    <Shell route={route} me={me}>
      <PageHead title="My Support Tickets" description="What you have reported to the Directorate of ICT, where each stands, and what the desk said."
        actions={<><LinkBtn kind="primary" href="/tickets/new">Submit a New Ticket</LinkBtn><LinkBtn href="/track">Track a Ticket</LinkBtn></>} />
      {!r.ok ? <ProblemNotice problem={r.problem} /> : null}
      <Tiles items={[
        ["Open", String(open.length), open.length ? "var(--amber-ink)" : null, "Submitted, opened, in progress or reopened"],
        ["Awaiting your confirmation", String(resolved.length), resolved.length ? "var(--green-ink)" : null, resolved.length ? "Confirm the resolution, or reopen" : "Nothing resolved awaits you"],
        ["Closed", String(rows.filter((t) => t.status === "CLOSED").length), null, "Settled tickets stay on your record"],
        ["All", String(rows.length), null, "Every ticket you have raised"],
      ]} />
      {resolved.length ? (
        <Note kind="ok" title={`${resolved.length} ticket${resolved.length === 1 ? " has" : "s have"} been marked as resolved`}
          action={<LinkBtn kind="go" href={`/tickets/${resolved[0].id}`}>Review {resolved[0].number}</LinkBtn>}>
          Open the ticket to read the resolution. Confirm it if the problem is settled, which closes the ticket; reopen it if it is not, and say what is still wrong.
        </Note>
      ) : null}
      <Panel title="Your tickets" right={rows.length ? `${open.length} open · ${rows.length} in all` : "None yet"}>
        {rows.length ? (
          <DTable cols={["Ticket", "Subject", "Category", "Status|mid", "Priority|mid", "Raised|mid", "Last updated|mid", "|num"]} rows={rows.map((t) => [
            <Link key="n" className="lnk tnum b600" href={`/tickets/${t.id}`}>{t.number}</Link>,
            <span key="s"><strong>{t.subject}</strong>{t.agent ? <div className="sub2">With {t.agent}</div> : null}</span>,
            <span key="c" className="sub2">{t.category}</span>,
            <StatusPil key="st" status={t.status} />,
            <PriorityPil key="p" priority={t.priority} />,
            <span key="r" className="tnum sub2">{when(t.created_at)}</span>,
            <span key="u" className="tnum sub2">{when(t.updated_at)}</span>,
            <LinkBtn key="o" href={`/tickets/${t.id}`} kind={t.status === "RESOLVED" ? "go" : "ghost"} size="sm">{t.status === "RESOLVED" ? "Review" : "Open"}</LinkBtn>,
          ])} texts={rows.map((t) => `${t.number} ${t.subject} ${t.category} ${t.status}`)} />
        ) : (
          <PBody>
            <div className="sub2">You have not raised a ticket yet. Report a payment that did not register, a login that fails, a course that will not register, a result, the portal, your email, your account or the network; you receive a tracking number at once and are told at every turn.</div>
            <div className="mt-3"><LinkBtn kind="primary" href="/tickets/new">Submit a New Ticket</LinkBtn></div>
          </PBody>
        )}
      </Panel>
    </Shell>
  );
}
