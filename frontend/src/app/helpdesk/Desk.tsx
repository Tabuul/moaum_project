"use client";
/** The ICT support desk (V251): the figures as KPI tiles, then the work queue — search, the filters, sorting and
 *  paging are query parameters, so a view can be bookmarked and the server does the work. */
import Link from "next/link";
import { useState } from "react";
import { useQueryNav } from "@/lib/query-nav";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { PRIORITY, PriorityPil, STATUS, StatusPil, hours, when, type Agent, type Category, type TicketRow } from "@/lib/helpdesk";

export interface Stats {
  totals: { total: number; submitted: number; opened: number; in_progress: number; reopened: number; resolved: number; closed: number; open: number; unassigned: number; high: number; overdue: number; response_overdue: number; escalated: number; avg_first_response_hours: number | null; avg_resolution_hours: number | null; avg_closure_hours: number | null; resolved_in_sla: number; ever_resolved: number; mine_open: number };
  byStatus: { key: string; n: number }[]; byCategory: { key: string; n: number; open: number }[]; byPriority: { key: string; n: number }[];
  byFaculty: { key: string; n: number }[]; byDepartment: { key: string; n: number }[]; byRequesterKind: { key: string; n: number }[];
  byAgent: { key: string; agent_id: string | null; n: number; open: number; done: number; overdue: number; avg_resolution_hours: number | null }[];
  monthly: { key: string; created: number; resolved: number; closed: number }[];
  sla: { priority: string; first_response_hours: number; resolution_hours: number }[];
}
interface Filters { q: string; status: string; category: string; priority: string; agent: string; from: string; to: string; sort: string; dir: string; size: string }

export function Desk({ me, director, queue, stats, categories, agents, filters }: {
  me: string; director: boolean; queue: { rows: TicketRow[]; total: number; page: number; size: number }; stats: Stats | null; categories: Category[]; agents: Agent[]; filters: Filters;
}) {
  const go = useQueryNav();
  const [q, setQ] = useState(filters.q);
  const [from, setFrom] = useState(filters.from);
  const [to, setTo] = useState(filters.to);
  const n = (v: number | null | undefined) => Number(v ?? 0);
  const t = stats?.totals;
  const size = queue.size || 20;
  const pages = Math.max(1, Math.ceil(queue.total / size));

  function nav(patch: Partial<Filters & { page: string }>) {
    const next: Record<string, string> = { ...filters, page: "1", ...patch };
    const qs = new URLSearchParams();
    for (const [k, v] of Object.entries(next)) if (v && !(k === "status" && v === "open") && !(k === "sort" && v === "updated") && !(k === "dir" && v === "desc") && !(k === "size" && v === "20") && !(k === "page" && v === "1")) qs.set(k, v);
    go(`/helpdesk${qs.toString() ? "?" + qs.toString() : ""}`);
  }
  const sortBy = (key: string) => nav({ sort: key, dir: filters.sort === key && filters.dir === "desc" ? "asc" : "desc" });
  const arrow = (key: string) => (filters.sort === key ? (filters.dir === "asc" ? " ↑" : " ↓") : "");
  const filtered = !!(filters.q || filters.category || filters.priority || filters.agent || filters.from || filters.to || filters.status !== "open");

  return (
    <>
      <PageHead title="ICT Support Desk" description="What students and staff have reported, where each ticket stands, and who has it."
        actions={<>
          {director ? <LinkBtn href="/helpdesk/reports">Reports and Analytics</LinkBtn> : null}
          {director ? <LinkBtn href="/helpdesk/settings">Categories and SLAs</LinkBtn> : null}
          <LinkBtn href="/tickets">My Own Tickets</LinkBtn>
        </>} />
      {t ? (
        <>
          <Tiles items={[
            ["Total tickets", String(n(t.total)), null, `${n(t.closed)} closed · ${n(t.resolved)} resolved`],
            ["New", String(n(t.submitted)), n(t.submitted) ? "var(--red-ink)" : null, "Submitted, not yet opened", "/helpdesk?status=SUBMITTED"],
            ["Opened", String(n(t.opened)), null, "Read by the desk, not yet in hand", "/helpdesk?status=OPENED"],
            ["In progress", String(n(t.in_progress) + n(t.reopened)), null, `${n(t.reopened)} reopened`, "/helpdesk?status=IN_PROGRESS,REOPENED"],
          ]} />
          <Tiles items={[
            ["Unassigned", String(n(t.unassigned)), n(t.unassigned) ? "var(--amber-ink)" : null, "Open, with no agent", "/helpdesk?agent=none"],
            ["High priority", String(n(t.high)), n(t.high) ? "var(--red-ink)" : null, "High or urgent, still open", "/helpdesk?sort=priority"],
            ["Overdue", String(n(t.overdue)), n(t.overdue) ? "var(--red-ink)" : null, `${n(t.response_overdue)} past first response · ${n(t.escalated)} escalated`],
            ["Average resolution", hours(t.avg_resolution_hours), null, `First response ${hours(t.avg_first_response_hours)} · ${n(t.ever_resolved) ? Math.round((100 * n(t.resolved_in_sla)) / n(t.ever_resolved)) + "% within SLA" : "no resolutions yet"}`],
          ]} />
          {n(t.mine_open) ? <Note kind="info" title={`${n(t.mine_open)} open ticket${n(t.mine_open) === 1 ? " is" : "s are"} with you`} action={<Btn kind="primary" size="sm" onClick={() => nav({ agent: "me", status: "open" })}>Show Mine</Btn>}>Tickets assigned to you that are not yet resolved.</Note> : null}
        </>
      ) : null}

      <form className="filterbar" onSubmit={(e) => { e.preventDefault(); nav({ q, from, to }); }}>
        <div className="row">
          <Field id="hd-q" label="Search" style={{ flex: "2 1 260px" }}>
            <input id="hd-q" className="ctl" type="search" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Number, subject, name, matric or staff number, email, payment reference" />
          </Field>
          <Field id="hd-status" label="Status" style={{ flex: "1 1 150px" }}>
            <select id="hd-status" className="ctl" value={filters.status} onChange={(e) => nav({ status: e.target.value })}>
              <option value="open">All open</option>
              {Object.entries(STATUS).map(([k, v]) => <option key={k} value={k}>{v[0]}</option>)}
              <option value="IN_PROGRESS,REOPENED">In progress or reopened</option>
              <option value="all">Everything</option>
            </select>
          </Field>
          <Field id="hd-cat" label="Category" style={{ flex: "1 1 160px" }}>
            <select id="hd-cat" className="ctl" value={filters.category} onChange={(e) => nav({ category: e.target.value })}>
              <option value="">Any</option>
              {categories.map((c) => <option key={c.code} value={c.code}>{c.name}</option>)}
            </select>
          </Field>
          <Field id="hd-pri" label="Priority" style={{ flex: "1 1 120px" }}>
            <select id="hd-pri" className="ctl" value={filters.priority} onChange={(e) => nav({ priority: e.target.value })}>
              <option value="">Any</option>
              {Object.entries(PRIORITY).map(([k, v]) => <option key={k} value={k}>{v[0]}</option>)}
            </select>
          </Field>
          <Field id="hd-agent" label="Agent" style={{ flex: "1 1 160px" }}>
            <select id="hd-agent" className="ctl" value={filters.agent} onChange={(e) => nav({ agent: e.target.value })}>
              <option value="">Any</option>
              <option value="me">Assigned to me</option>
              <option value="none">Unassigned</option>
              {agents.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}
            </select>
          </Field>
          <Field id="hd-from" label="Raised from" style={{ flex: "1 1 140px" }}><input id="hd-from" className="ctl" type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></Field>
          <Field id="hd-to" label="To" style={{ flex: "1 1 140px" }}><input id="hd-to" className="ctl" type="date" value={to} onChange={(e) => setTo(e.target.value)} /></Field>
          <div className="row row--tight" style={{ alignSelf: "flex-end" }}>
            <Btn kind="primary" type="submit">Search</Btn>
            {filtered ? <Btn kind="ghost" onClick={() => { setQ(""); setFrom(""); setTo(""); go("/helpdesk"); }}>Clear</Btn> : null}
          </div>
        </div>
      </form>

      <Panel title="The queue" right={`${queue.total} ticket${queue.total === 1 ? "" : "s"}${filters.status === "open" ? " open" : ""}`}>
        <PBody>
          <div className="row row--base">
            <span className="sub2">Sort by</span>
            {[["updated", "Updated"], ["created", "Raised"], ["priority", "Priority"], ["status", "Status"], ["due", "Due"], ["number", "Number"]].map(([k, l]) => (
              <Btn key={k} kind={filters.sort === k ? "primary" : "ghost"} size="sm" onClick={() => sortBy(k)}>{l}{arrow(k)}</Btn>
            ))}
          </div>
        </PBody>
        {queue.rows.length ? (
          <DTable pageSize={0} cols={["Ticket", "Requester", "Category", "Subject", "Priority|mid", "Status|mid", "Agent", "Raised|mid", "Updated|mid", "|num"]} rows={queue.rows.map((r) => [
            <span key="n"><Link className="lnk tnum b600" href={`/helpdesk/tickets/${r.id}`}>{r.number}</Link>{r.overdue ? <div><Pil kind="bad">Overdue</Pil></div> : r.response_overdue ? <div><Pil kind="warn">No response yet</Pil></div> : null}</span>,
            <span key="r"><strong>{r.requester_name}</strong><div className="sub2 tnum">{r.requester_number ?? r.requester_email ?? ""} · {r.requester_kind === "STUDENT" ? "Student" : "Staff"}</div></span>,
            <span key="c" className="sub2">{r.category}</span>,
            <span key="s">{r.subject}{r.escalated ? <div><Pil kind="warn">Escalated</Pil></div> : null}</span>,
            <PriorityPil key="p" priority={r.priority} />,
            <StatusPil key="st" status={r.status} />,
            <span key="a" className={r.agent ? "" : "sub2"}>{r.agent ?? "Unassigned"}{r.assigned_to === me ? <div><Pil kind="info">You</Pil></div> : null}</span>,
            <span key="cr" className="tnum sub2">{when(r.created_at)}</span>,
            <span key="up" className="tnum sub2">{when(r.updated_at)}</span>,
            <LinkBtn key="o" href={`/helpdesk/tickets/${r.id}`} kind={r.status === "SUBMITTED" ? "primary" : "ghost"} size="sm">Open</LinkBtn>,
          ])} />
        ) : <PBody><div className="sub2">No ticket matches. Widen the filters, or clear them.</div></PBody>}
        <PBody>
          <div className="row row--base">
            <span className="grow" />
            <span className="sub2 tnum">Page {queue.page} of {pages}</span>
            <Btn kind="ghost" size="sm" disabled={queue.page <= 1} onClick={() => nav({ page: String(queue.page - 1) })}>Previous</Btn>
            <Btn kind="ghost" size="sm" disabled={queue.page >= pages} onClick={() => nav({ page: String(queue.page + 1) })}>Next</Btn>
            <select className="ctl" value={filters.size} onChange={(e) => nav({ size: e.target.value })} aria-label="Rows a page">
              {["10", "20", "50", "100"].map((s) => <option key={s} value={s}>{s} a page</option>)}
            </select>
          </div>
        </PBody>
      </Panel>

      {stats && director ? (
        <div className="grid grid--2">
          <Panel title="Agent workload" right="Open tickets with each agent">
            <DTable cols={["Agent", "Open|mid", "Overdue|mid", "Done|mid", "Avg resolution|mid"]} rows={stats.byAgent.map((a, i) => [
              <span key={"a" + i}>{a.agent_id ? <Link className="lnk" href={`/helpdesk?agent=${a.agent_id}`}>{a.key}</Link> : <span className="sub2">{a.key}</span>}</span>,
              <span key={"o" + i} className="tnum">{n(a.open)}</span>,
              <span key={"v" + i} className={`tnum${n(a.overdue) ? " ink-red" : ""}`}>{n(a.overdue)}</span>,
              <span key={"d" + i} className="tnum">{n(a.done)}</span>,
              <span key={"h" + i} className="tnum sub2">{hours(a.avg_resolution_hours)}</span>,
            ])} />
          </Panel>
          <Panel title="Tickets by category" right="All time">
            <DTable cols={["Category", "Open|mid", "All|mid", ""]} rows={stats.byCategory.map((c, i) => {
              const max = Math.max(1, ...stats.byCategory.map((x) => n(x.n)));
              return [
                <span key={"c" + i}>{c.key}</span>,
                <span key={"o" + i} className="tnum">{n(c.open)}</span>,
                <span key={"n" + i} className="tnum">{n(c.n)}</span>,
                <span key={"b" + i} className="meter"><span className="meter__bar"><span className="meter__fill" style={{ width: `${Math.round((100 * n(c.n)) / max)}%` }} /></span></span>,
              ];
            })} />
          </Panel>
        </div>
      ) : null}
    </>
  );
}
