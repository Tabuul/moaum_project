import Link from "next/link";
import { api } from "@/lib/api";
import { LinkBtn, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ACTION, AVAILABILITY, PRIORITY, hours, statusWord, when, type Activity, type Counts, type Queue, type Workload } from "@/lib/helpdesk";
import { DeskStats, type Stats } from "./DeskStats";

/** What the desk reads after the tickets (October 2026): the operations — the queues' load, the agents' load, the last acts — and
 *  the figures. An async server component streamed in behind the ticket workspace, so the slower analytics queries never
 *  hold the queue back; a figure that cannot be read leaves its panel saying so and nothing else. */
export async function DeskLater({ head, queues, counts }: { head: boolean; queues: Queue[]; counts?: Counts | null }) {
  const [stats, activity, workload] = await Promise.all([
    api<Stats>("/api/v1/helpdesk/stats"),
    api<Activity[]>("/api/v1/helpdesk/activity?limit=15"),
    head ? api<Workload[]>("/api/v1/helpdesk/workload") : Promise.resolve(null),
  ]);
  const n = (v: number | null | undefined) => Number(v ?? 0);
  const live = queues.filter((x) => x.active);
  const acts = activity.ok ? activity.data : [];
  return (
    <>
      <Panel title="Student support" right="Resolve from the student's record — every act on the ledger and the ticket">
        <PBody>
          <form action="/helpdesk/students" method="get" className="row" style={{ flexWrap: "wrap", gap: "var(--s-3)", alignItems: "flex-end" }}>
            <div className="field" style={{ flex: "3 1 320px" }}>
              <label htmlFor="dl-q">Student search</label>
              <input id="dl-q" name="q" className="ctl" type="search" placeholder="Name, matriculation, JAMB or application number, student ID" />
            </div>
            <button type="submit" className="btn btn--primary btn--sm">Find the student</button>
            <LinkBtn href="/helpdesk/payments" size="sm">Payment Support</LinkBtn>
            <LinkBtn href="/helpdesk/audit" size="sm">Support Action History</LinkBtn>
          </form>
        </PBody>
        <PBody>
          <div className="grid grid--4">
            {([["Course registration issues", counts?.registration_issues, "/helpdesk?category=REGISTRATION"], ["Payment issues", counts?.payment_issues, "/helpdesk?category=PAYMENT"],
               ["Password reset requests", counts?.password_issues, "/helpdesk?category=LOGIN"], ["Escalated issues", counts?.escalated, "/helpdesk?status=escalated"]] as [string, number | undefined, string][]).map(([label, v, href]) => (
              <Link key={label} className="tile" href={href} style={{ textDecoration: "none", color: "inherit" }}>
                <span className="eyebrow">{label}</span>
                <span className="n tnum">{v == null ? "—" : n(v)}</span>
                <span className="c">open, within your scope</span>
              </Link>
            ))}
          </div>
        </PBody>
      </Panel>

      <Panel title="Support operations" right={head ? <LinkBtn href="/helpdesk/agents" size="sm">Agents, queues and routing</LinkBtn> : "The queues you are posted on"}>
        {live.length ? (
          <DTable pageSize={0} noPrint cols={["Queue", "Office that decides", "Agents|mid", "Open|mid", "Unassigned|mid", "Waiting|mid", "Overdue|mid", "Critical|mid", "|num"]} rows={live.map((x) => [
            <span key="q"><Link className="lnk b600" href={`/helpdesk?queue=${x.code}`}>{x.name}</Link></span>,
            <span key="o" className="sub2">{x.office ?? "—"}</span>,
            <span key="a" className={`tnum${!n(x.available_agents) && n(x.open) ? " ink-red" : ""}`}>{n(x.available_agents)}<span className="sub2"> of {n(x.agents)}</span></span>,
            <span key="n" className="tnum">{n(x.open)}</span>,
            <span key="u" className={`tnum${n(x.unassigned) ? " ink-amber b600" : ""}`}>{n(x.unassigned)}</span>,
            <span key="w" className="tnum">{n(x.waiting_student) + n(x.waiting_office)}</span>,
            <span key="v" className={`tnum${n(x.overdue) ? " ink-red b600" : ""}`}>{n(x.overdue)}</span>,
            <span key="c" className={`tnum${n(x.critical) ? " ink-red b600" : ""}`}>{n(x.critical)}</span>,
            <LinkBtn key="g" href={`/helpdesk?queue=${x.code}${n(x.unassigned) ? "&agent=none" : ""}`} size="sm">{n(x.unassigned) ? "Unassigned" : "Open"}</LinkBtn>,
          ])} />
        ) : <PBody><div className="sub2">No active queue yet.</div></PBody>}
      </Panel>

      {head && workload ? (
        <Panel title="Agent workload" right="Open tickets with each agent, the overdue and critical among them, and the pace">
          {workload.ok && workload.data.length ? (
            <DTable pageSize={0} noPrint cols={["Agent", "Queues", "Availability|mid", "Open|mid", "Waiting|mid", "Overdue|mid", "Critical|mid", "This week|mid", "Avg|mid", "|num"]} rows={workload.data.map((w) => [
              <span key="a"><strong>{w.name}</strong><div className="sub2">{w.scopes ?? ""}</div></span>,
              <span key="q" className="sub2">{w.queues ?? "—"}</span>,
              <Pil key="v" kind={AVAILABILITY[w.availability]?.[1] ?? "grey"}>{AVAILABILITY[w.availability]?.[0] ?? w.availability}</Pil>,
              <span key="o" className="tnum">{n(w.open)}</span>,
              <span key="w" className="tnum">{n(w.waiting)}</span>,
              <span key="d" className={`tnum${n(w.overdue) ? " ink-red b600" : ""}`}>{n(w.overdue)}</span>,
              <span key="c" className={`tnum${n(w.critical) ? " ink-red" : ""}`}>{n(w.critical)}</span>,
              <span key="r" className="tnum">{n(w.resolved_week)}</span>,
              <span key="h" className="tnum sub2">{hours(w.avg_resolution_hours)}</span>,
              <LinkBtn key="x" size="sm" href={`/helpdesk?agent=${w.person_id}`}>Tickets</LinkBtn>,
            ])} />
          ) : <PBody><div className="sub2">{workload.ok ? "No agent holds a ticket yet." : "The agents' workload is temporarily unavailable."}</div></PBody>}
        </Panel>
      ) : null}

      <Panel title="Lately on the desk" right={acts.length ? "The last acts on the tickets you can see, newest first" : "Nothing yet"}>
        {acts.length ? (
          <DTable pageSize={0} noPrint cols={["When|mid", "Ticket", "What", "By"]} rows={acts.map((a) => {
            const change = ["STATUS_CHANGED", "OPENED", "REOPENED", "CLOSED", "RESOLUTION", "WAITING"].includes(a.action) ? [a.from_value, a.to_value].filter(Boolean).map((v) => statusWord(v!)).join(" → ")
              : ["ASSIGNED", "REASSIGNED", "ESCALATED", "ROUTED", "QUEUED", "TRANSFERRED", "ESCALATED_TO_OFFICE", "OFFICE_ANSWERED", "RETURNED"].includes(a.action) ? [a.from_value, a.to_value].filter(Boolean).join(" → ")
              : a.action === "PRIORITY_CHANGED" ? [a.from_value, a.to_value].filter(Boolean).map((v) => PRIORITY[v!]?.[0] ?? v).join(" → ") : "";
            return [
              <span key="w" className="tnum sub2">{when(a.at)}</span>,
              <span key="t"><Link className="lnk tnum b600" href={`/helpdesk/tickets/${a.ticket_id}`}>{a.number}</Link><div className="sub2">{a.subject}</div></span>,
              <span key="a"><strong>{ACTION[a.action] ?? a.action}</strong>{change ? <span className="sub2"> · {change}</span> : null}{a.internal ? <> <Pil kind="grey">Internal</Pil></> : null}{a.detail && !["ASSIGNED", "REASSIGNED"].includes(a.action) ? <div className="sub2">{a.detail.length > 120 ? a.detail.slice(0, 120) + "…" : a.detail}</div> : null}</span>,
              <span key="b" className="sub2">{a.actor_name}{a.actor_kind === "REQUESTER" ? " (requester)" : ""}</span>,
            ];
          })} />
        ) : <PBody><div className="sub2">Every act on every ticket you can see lands here as it happens.</div></PBody>}
      </Panel>

      <DeskStats stats={stats.ok ? stats.data : null} head={head} />
    </>
  );
}

/** what shows while the operations and the figures are still on their way */
export function DeskLaterFallback() {
  return (
    <Panel title="Support operations and statistics" right="Loading…">
      <PBody><div className="sub2">The queues&rsquo; load, the agents&rsquo; load, the last acts and the figures follow in a moment. The ticket queue above is ready.</div></PBody>
    </Panel>
  );
}
