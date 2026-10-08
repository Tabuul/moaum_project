"use client";
/** The ICT support desk, ticket-first (V251, queues V328, rearranged ticket-first in October 2026): what needs attention now comes first —
 *  the search and the filters, the counts that filter the list in place, then the ticket queue itself with the acts on
 *  each row; the operations and the figures stream in below it (DeskLater). Search, filters, sorting and paging are
 *  query parameters answered by the server, so a view can be bookmarked and no ticket is loaded that is not shown. */
import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { useQueryNav } from "@/lib/query-nav";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { SearchSelect } from "@/components/proto/SearchSelect";
import { AVAILABILITY, PRIORITY, PriorityPil, STATUS, StatusPil, when, type Agent, type Category, type Counts, type Queue, type TicketRow } from "@/lib/helpdesk";
import { Ago, Due } from "@/components/helpdesk/Clock";

export interface Filters { q: string; status: string; category: string; priority: string; agent: string; queue: string; faculty: string; department: string; from: string; to: string; sort: string; dir: string; size: string }
export interface Faculty { code: string; name: string; departments: { code: string; name: string }[] }

/** the status list as the desk filters it: the ticket's own states, and the desk's questions (new, unassigned, escalated, overdue) */
const STATUS_OPTIONS: [string, string][] = [
  ["open", "All open"], ["new", "New (submitted, not yet opened)"], ["unassigned", "Unassigned"], ["active", "Opened, in progress or reopened"],
  ["IN_PROGRESS", "In progress"], ["WAITING_FOR_STUDENT", "Waiting for requester"], ["WAITING_FOR_OFFICE", "With an office"], ["waiting", "Waiting (either)"],
  ["escalated", "Escalated"], ["overdue", "Overdue (past the SLA)"], ["RESOLVED", "Resolved"], ["CLOSED", "Closed"], ["REOPENED", "Reopened"], ["all", "Everything"],
];
const POLL_MS = 60_000;

export function Desk({ me, head, queue, counts, categories, agents, queues, faculties, filters }: {
  me: string; head: boolean; queue: { rows: TicketRow[]; total: number; page: number; size: number }; counts: Counts | null;
  categories: Category[]; agents: Agent[]; queues: Queue[]; faculties: Faculty[]; filters: Filters;
}) {
  const go = useQueryNav();
  const router = useRouter();
  const [busy, setBusy] = useState<string | null>(null);
  const [q, setQ] = useState(filters.q);
  const [from, setFrom] = useState(filters.from);
  const [to, setTo] = useState(filters.to);
  const [assign, setAssign] = useState<{ t: TicketRow; agents: Agent[] | null; agent: string; reason: string } | null>(null);
  const [arrived, setArrived] = useState(0);
  const baseline = useRef<{ n: number; latest: string | null }>({ n: counts?.new ?? 0, latest: counts?.latest_new ?? null });
  const n = (v: number | null | undefined) => Number(v ?? 0);
  const size = queue.size || 20;
  const pages = Math.max(1, Math.ceil(queue.total / size));
  const first = (queue.page - 1) * size;

  // the state filter as the URL carries it: a ticket state is `status`, the desk's questions are their own parameters
  const statusValue = filters.status === "open" && filters.agent === "none" ? "unassigned" : filters.status;
  function nav(patch: Partial<Filters & { page: string }>) {
    const next: Record<string, string> = { ...filters, page: "1", ...patch };
    if (patch.status !== undefined) {
      next.agent = patch.status === "unassigned" ? "none" : filters.agent === "none" ? "" : filters.agent;
      next.status = patch.status === "unassigned" ? "open" : patch.status;
    }
    const qs = new URLSearchParams();
    for (const [k, v] of Object.entries(next)) if (v && !(k === "status" && v === "open") && !(k === "sort" && v === "priority") && !(k === "dir" && v === "desc") && !(k === "size" && v === "20") && !(k === "page" && v === "1")) qs.set(k, v);
    go(`/helpdesk${qs.toString() ? "?" + qs.toString() : ""}`);
  }
  const sortBy = (key: string) => nav({ sort: key, dir: filters.sort === key && filters.dir === "desc" ? "asc" : "desc" });
  const arrow = (key: string) => (filters.sort === key ? (filters.dir === "asc" ? " ↑" : " ↓") : "");
  const filtered = !!(filters.q || filters.category || filters.priority || filters.agent || filters.queue || filters.faculty || filters.department || filters.from || filters.to || filters.status !== "open");
  const settled = (r: TicketRow) => r.status === "RESOLVED" || r.status === "CLOSED";
  const departments = (faculties.find((f) => f.code === filters.faculty)?.departments ?? faculties.flatMap((f) => f.departments)).map((d) => ({ value: d.code, label: d.name }));

  async function post(path: string, body: unknown, reason: string, key: string): Promise<boolean> {
    setBusy(key);
    try {
      const res = await fetch(`/api/bff/api/v1/helpdesk/tickets/${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body) });
      if (!res.ok) { notifyProblem((await res.json().catch(() => null)) ?? { status: res.status, title: res.statusText }); return false; }
      notify(reason);
      router.refresh();
      return true;
    } finally { setBusy(null); }
  }
  /** take a ticket straight from the queue: assigned to you, opened if it was only submitted */
  const take = (r: TicketRow) => void post(`${r.id}/assign`, { agentId: me }, `${r.number}: taken from the queue`, r.id);
  /** assign from the queue: the agents read against the ticket, so the eligible — posted on its queue, covering its faculty — come first */
  async function openAssign(r: TicketRow) {
    setAssign({ t: r, agents: null, agent: "", reason: "" });
    try {
      const res = await fetch(`/api/bff/api/v1/helpdesk/agents?ticket=${encodeURIComponent(r.id)}`);
      const list = res.ok ? ((await res.json()) as Agent[]) : agents;
      const ranked = [...list].sort((a, b) => Number(!!b.posted) - Number(!!a.posted) || Number(!!b.eligible) - Number(!!a.eligible) || Number(a.open) - Number(b.open) || a.name.localeCompare(b.name));
      setAssign((s) => (s && s.t.id === r.id ? { ...s, agents: ranked } : s));
    } catch {
      setAssign((s) => (s && s.t.id === r.id ? { ...s, agents } : s));
    }
  }
  const describe = (a: Agent) => `${a.posted ? "Posted here · " : a.eligible ? "Eligible · " : ""}${a.name} · ${a.queues ?? a.offices}${a.scopes ? ` (${a.scopes})` : ""} · ${a.open} open${a.availability && a.availability !== "AVAILABLE" ? ` · ${AVAILABILITY[a.availability]?.[0] ?? a.availability}` : ""}`;

  // a new ticket arriving while the desk is open: the counts are asked again now and then, cheaply, and the desk is told
  useEffect(() => {
    let stop = false;
    const tick = async () => {
      try {
        const res = await fetch("/api/bff/api/v1/helpdesk/counts");
        if (!res.ok || stop) return;
        const c = (await res.json()) as Counts;
        const newer = c.latest_new && (!baseline.current.latest || new Date(c.latest_new) > new Date(baseline.current.latest));
        if (newer || n(c.new) > baseline.current.n) setArrived(Math.max(1, n(c.new) - baseline.current.n));
      } catch { /* the desk stays as it is; the next tick tries again */ }
    };
    const id = window.setInterval(() => void tick(), POLL_MS);
    return () => { stop = true; window.clearInterval(id); };
  }, []);
  // what the reader is looking at: counts clicked filter the list in place
  const chip = (label: string, value: number, patch: Partial<Filters>, active: boolean, tone: "bad" | "warn" | "info" | "grey" | "ok" = "grey") => (
    <button key={label} type="button" role="tab" className="tabs__t" aria-selected={active} onClick={() => nav({ q: "", ...patch })} style={{ display: "inline-flex", alignItems: "center", gap: 8 }}>
      <span>{label}</span>
      <Pil kind={value ? tone : "grey"}>{value}</Pil>
    </button>
  );
  const is = (status: string, agent = "") => statusValue === status && (agent ? filters.agent === agent : filters.agent !== "me");
  const mineIs = (status: string) => filters.agent === "me" && filters.status === status;

  return (
    <>
      <PageHead title="ICT support desk" description={head ? "What needs attention now across the University's support queues, then the operations and the figures." : "What needs your attention now, within the queues you are posted on."}
        actions={<>
          {head ? <LinkBtn href="/helpdesk/agents">Agents, Queues and Routing</LinkBtn> : null}
          {head ? <LinkBtn href="/helpdesk/reports">Reports and Analytics</LinkBtn> : null}
          <LinkBtn href="/helpdesk/students" kind="secondary">Student Support</LinkBtn>
          <LinkBtn href="/tickets">My Own Tickets</LinkBtn>
        </>} />

      {arrived ? (
        <Note kind="info" title={`${arrived === 1 ? "A new support ticket has" : `${arrived} new support tickets have`} arrived since you opened the desk`}
          action={<Btn kind="primary" size="sm" onClick={() => { baseline.current = { n: baseline.current.n + arrived, latest: null }; setArrived(0); router.refresh(); }}>Refresh the Queue</Btn>}>
          The queue below is as it was when the page loaded. Refresh to bring the new ticket{arrived === 1 ? "" : "s"} in.
        </Note>
      ) : null}

      <Panel title="Support tickets" right={counts ? `${n(counts.open)} open within your scope` : "Counts unavailable"}>
        <PBody>
          <form className="row" onSubmit={(e) => { e.preventDefault(); nav({ q, from, to }); }} role="search" aria-label="Search tickets">
            <Field id="hd-q" label="Search tickets" style={{ flex: "3 1 320px" }}>
              <input id="hd-q" className="ctl" type="search" value={q} onChange={(e) => setQ(e.target.value)} placeholder="Ticket number, student or staff name, matric or staff number, email, subject, payment reference, username" />
            </Field>
            <Field id="hd-status" label="Status" style={{ flex: "1 1 190px" }}>
              <select id="hd-status" className="ctl" value={statusValue} onChange={(e) => nav({ status: e.target.value })}>
                {STATUS_OPTIONS.map(([k, l]) => <option key={k} value={k}>{l}</option>)}
              </select>
            </Field>
            <Field id="hd-pri" label="Priority" style={{ flex: "1 1 120px" }}>
              <select id="hd-pri" className="ctl" value={filters.priority} onChange={(e) => nav({ priority: e.target.value })}>
                <option value="">Any</option>
                {Object.entries(PRIORITY).map(([k, v]) => <option key={k} value={k}>{v[0]}</option>)}
              </select>
            </Field>
            <Field id="hd-cat" label="Category" style={{ flex: "1 1 170px" }}>
              <SearchSelect id="hd-cat" value={filters.category} onChange={(v) => nav({ category: v })} allLabel="Any category" options={categories.map((c) => ({ value: c.code, label: c.name }))} />
            </Field>
            <Field id="hd-queue" label="Queue" style={{ flex: "1 1 170px" }}>
              <SearchSelect id="hd-queue" value={filters.queue} onChange={(v) => nav({ queue: v })} allLabel="Any queue" options={queues.map((x) => ({ value: x.code, label: `${x.name}${x.active ? "" : " (inactive)"}` }))} />
            </Field>
            <Field id="hd-agent" label="Agent" style={{ flex: "1 1 170px" }}>
              <SearchSelect id="hd-agent" value={filters.agent} onChange={(v) => nav({ agent: v })} allLabel="Any agent"
                options={[{ value: "me", label: "Assigned to me" }, { value: "none", label: "Unassigned" }, ...agents.map((a) => ({ value: a.id, label: a.name }))]} />
            </Field>
            <Field id="hd-fac" label="Faculty" style={{ flex: "1 1 170px" }}>
              <SearchSelect id="hd-fac" value={filters.faculty} onChange={(v) => nav({ faculty: v, department: "" })} allLabel="Any faculty" options={faculties.map((f) => ({ value: f.code, label: f.name }))} />
            </Field>
            <Field id="hd-dep" label="Department" style={{ flex: "1 1 170px" }}>
              <SearchSelect id="hd-dep" value={filters.department} onChange={(v) => nav({ department: v })} allLabel="Any department" options={departments} />
            </Field>
            <Field id="hd-from" label="Raised from" style={{ flex: "1 1 130px" }}><input id="hd-from" className="ctl" type="date" value={from} onChange={(e) => setFrom(e.target.value)} /></Field>
            <Field id="hd-to" label="To" style={{ flex: "1 1 130px" }}><input id="hd-to" className="ctl" type="date" value={to} onChange={(e) => setTo(e.target.value)} /></Field>
            <div className="row row--tight" style={{ alignSelf: "flex-end" }}>
              <Btn kind="primary" type="submit">Search</Btn>
              {filtered ? <Btn kind="ghost" onClick={() => { setQ(""); setFrom(""); setTo(""); go("/helpdesk"); }}>Clear</Btn> : null}
            </div>
          </form>

          {counts ? (
            <div className="mt-3">
              {!head || n(counts.mine) ? (
                <div className="row row--base mb-2" role="group" aria-label="Your tickets">
                  <span className="sub2" style={{ minWidth: 72 }}>With you</span>
                  <div className="tabs" role="tablist" aria-label="Your tickets">
                    {chip("My assigned", n(counts.mine), { agent: "me", status: "open" }, mineIs("open"), "info")}
                    {chip("My new", n(counts.mine_new), { agent: "me", status: "SUBMITTED,OPENED" }, mineIs("SUBMITTED,OPENED"), "bad")}
                    {chip("In progress", n(counts.mine_in_progress), { agent: "me", status: "active" }, mineIs("active"), "info")}
                    {chip("Waiting", n(counts.mine_waiting), { agent: "me", status: "waiting" }, mineIs("waiting"), "warn")}
                    {chip("Escalated", n(counts.mine_escalated), { agent: "me", status: "escalated" }, mineIs("escalated"), "warn")}
                    {chip("Overdue", n(counts.mine_overdue), { agent: "me", status: "overdue" }, mineIs("overdue"), "bad")}
                  </div>
                </div>
              ) : null}
              <div className="row row--base" role="group" aria-label={head ? "The desk" : "Your queues"}>
                <span className="sub2" style={{ minWidth: 72 }}>{head ? "The desk" : "Your queues"}</span>
                <div className="tabs" role="tablist" aria-label={head ? "The desk" : "Your queues"}>
                  {chip("New", n(counts.new), { status: "new", agent: "" }, is("new"), "bad")}
                  {chip("Unassigned", n(counts.unassigned), { status: "unassigned" }, is("unassigned", "none"), "warn")}
                  {chip("Urgent", n(counts.urgent), { status: "open", agent: "", priority: "" }, false, "bad")}
                  {chip("Escalated", n(counts.escalated), { status: "escalated", agent: "" }, is("escalated"), "warn")}
                  {chip("Overdue", n(counts.overdue), { status: "overdue", agent: "" }, is("overdue"), "bad")}
                  {chip("Waiting", n(counts.waiting), { status: "waiting", agent: "" }, is("waiting"), "info")}
                  {chip("All open", n(counts.open), { status: "open", agent: "", priority: "" }, is("open") && !filters.priority, "grey")}
                </div>
                <span className="sub2">Urgent counts urgent and critical; sort by priority puts them first.</span>
              </div>
            </div>
          ) : <div className="sub2 mt-3">The counts are temporarily unavailable; the queue below still answers.</div>}
        </PBody>
      </Panel>

      <Panel title={filters.queue ? `${queues.find((x) => x.code === filters.queue)?.name ?? filters.queue} queue` : filters.agent === "me" ? "With you" : "Ticket queue"}
        right={<span className="row row--inline row--tight">
          <span className="sub2">{queue.total} ticket{queue.total === 1 ? "" : "s"}{filters.status === "open" && filters.agent !== "none" ? " open" : ""} · sorted by</span>
          {[["priority", "Priority"], ["updated", "Updated"], ["created", "Raised"], ["due", "Due"], ["status", "Status"], ["queue", "Queue"]].map(([k, l]) => (
            <Btn key={k} kind={filters.sort === k ? "primary" : "ghost"} size="sm" onClick={() => sortBy(k)}>{l}{arrow(k)}</Btn>
          ))}
        </span>}>
        {queue.rows.length ? (
          <DTable pageSize={0} cols={["S/N|num", "Priority|mid", "Ticket", "Requester", "Category", "Subject", "Queue", "Agent", "Status|mid", "Raised|mid", "SLA|mid", "|num"]} rows={queue.rows.map((r, i) => {
            const isNew = r.status === "SUBMITTED";
            const unassigned = !r.assigned_to && !settled(r);
            const hot = r.priority === "CRITICAL" || r.priority === "URGENT";
            return [
              <span key="sn" className="tnum sub2">{first + i + 1}</span>,
              <span key="p" className={hot ? "b600" : ""}><PriorityPil priority={r.priority} /></span>,
              <span key="n"><Link className="lnk tnum b600" href={`/helpdesk/tickets/${r.id}`}>{r.number}</Link>
                <div className="row row--inline row--tight mt-1">
                  {isNew ? <Pil kind="bad">New</Pil> : null}
                  {r.overdue ? <Pil kind="bad">Overdue</Pil> : r.response_overdue ? <Pil kind="warn">No response yet</Pil> : null}
                  {r.escalated ? <Pil kind="warn">Escalated</Pil> : null}
                  {r.office ? <Pil kind="warn">With {r.office}</Pil> : null}
                </div></span>,
              <span key="r"><strong>{r.requester_name}</strong><div className="sub2 tnum">{r.requester_number ?? r.requester_email ?? ""} · {r.requester_kind === "STUDENT" ? "Student" : "Staff"}</div></span>,
              <span key="c" className="sub2">{r.category}</span>,
              <span key="s">{r.subject}{r.faculty ? <div className="sub2">{r.faculty}{r.department ? ` · ${r.department}` : ""}</div> : null}</span>,
              <span key="qu" className={r.queue ? "" : "sub2"}>{r.queue ?? "No queue"}</span>,
              <span key="a">{r.agent ? <>{r.agent}{r.assigned_to === me ? <div><Pil kind="info">You</Pil></div> : null}</> : unassigned ? <Pil kind="warn">Unassigned</Pil> : <span className="sub2">—</span>}</span>,
              <StatusPil key="st" status={r.status} />,
              <span key="cr" className="tnum sub2" title={`Raised ${when(r.created_at)} · updated ${when(r.updated_at)}`}><Ago iso={r.created_at} /><div>upd. <Ago iso={r.updated_at} /></div></span>,
              <span key="due" className={`tnum${r.overdue ? " ink-red b600" : settled(r) ? " sub2" : ""}`} title={when(r.due_at)}><Due iso={r.due_at} settled={settled(r)} /></span>,
              <span key="o" className="row row--inline row--tight row--right">
                {unassigned ? <Btn kind="secondary" size="sm" disabled={busy === r.id} onClick={() => take(r)}>{busy === r.id ? "Taking…" : "Take"}</Btn> : null}
                {!settled(r) ? <Btn kind="ghost" size="sm" disabled={busy === r.id} onClick={() => void openAssign(r)}>{r.assigned_to ? "Reassign" : "Assign"}</Btn> : null}
                <LinkBtn href={`/helpdesk/tickets/${r.id}`} kind={isNew ? "primary" : "ghost"} size="sm">Open</LinkBtn>
              </span>,
            ];
          })} />
        ) : (
          <PBody>
            <div className="sub2">
              {statusValue === "unassigned" ? "All current tickets have been assigned." : statusValue === "overdue" ? "No ticket is past its SLA." : statusValue === "escalated" ? "No ticket is escalated." : statusValue === "new" ? "No new ticket awaits opening." : filters.priority === "URGENT" || filters.priority === "CRITICAL" ? "No urgent tickets." : filtered ? "No ticket matches these filters. Widen them, or clear them." : "No support tickets require attention at this time."}
            </div>
          </PBody>
        )}
        <PBody>
          <div className="row row--base">
            <span className="sub2">{queue.total ? `Showing ${first + 1}–${Math.min(first + queue.rows.length, queue.total)} of ${queue.total}` : ""}</span>
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

      {assign ? (
        <Modal title={assign.t.agent ? `Reassign ${assign.t.number}` : `Assign ${assign.t.number}`} sub={`${assign.t.category}${assign.t.queue ? ` · ${assign.t.queue} queue` : ""} · ${assign.t.subject}`} onClose={() => setAssign(null)}
          foot={<><Btn kind="ghost" onClick={() => setAssign(null)}>Cancel</Btn><Btn kind="primary" disabled={busy !== null || !assign.agent || assign.agent === assign.t.assigned_to} onClick={async () => { if (await post(`${assign.t.id}/assign`, { agentId: assign.agent, reason: assign.reason.trim() || null }, `${assign.t.number}: ${assign.t.agent ? "reassigned" : "assigned"} to ${assign.agents?.find((a) => a.id === assign.agent)?.name ?? "an agent"}`, assign.t.id)) setAssign(null); }}>{assign.t.agent ? "Reassign" : "Assign"}</Btn></>}>
          <div className="stack">
            <Field id="hd-qa-agent" label="Agent" required hint={assign.agents === null ? "Reading who is eligible…" : assign.agents.some((a) => a.eligible) ? "The agents the routing would choose are first: posted on this queue, covering this faculty or department, available." : "No posted agent covers this ticket; any agent of the desk may take it."}>
              <select id="hd-qa-agent" className="ctl" value={assign.agent} disabled={assign.agents === null} onChange={(e) => setAssign({ ...assign, agent: e.target.value })}>
                <option value="">Choose…</option>
                {(assign.agents ?? []).map((a) => <option key={a.id} value={a.id}>{describe(a)}</option>)}
              </select>
            </Field>
            <Field id="hd-qa-reason" label="Note" hint="Optional; goes on the history"><input id="hd-qa-reason" className="ctl" value={assign.reason} onChange={(e) => setAssign({ ...assign, reason: e.target.value })} maxLength={500} /></Field>
          </div>
        </Modal>
      ) : null}
    </>
  );
}

/** the status pill's word for a filter value, for the empty states and titles */
export const statusLabel = (s: string) => STATUS[s]?.[0] ?? STATUS_OPTIONS.find(([k]) => k === s)?.[1] ?? s;
