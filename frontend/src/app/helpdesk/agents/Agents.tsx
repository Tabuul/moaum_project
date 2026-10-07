"use client";
/** The Head of ICT Support Desk's configuration (V328), in three tabs:
 *    Agents  — who is posted on which queue within what scope (the University, a faculty, a college, a department, an office),
 *              their availability and dates; an agent taken off the desk holds nothing — their open tickets return to the queue.
 *              Only a person who holds the ICT Support Agent office can be posted: support access comes from that office.
 *    Queues  — the support queues and the University office each answers to (its escalation office); deactivated, never deleted.
 *    Routing — where each category of problem goes, optionally per faculty or department, and how the agent is chosen. */
import { CAPABILITIES } from "@/lib/support";
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { useQueryNav } from "@/lib/query-nav";
import { reasonHeader } from "@/lib/reason";
import { notify, notifyProblem } from "@/components/proto/Toast";
import { Btn, LinkBtn, Note, PageHead, Panel, PBody, Pil, Tabs, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, Modal } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";
import { AVAILABILITY, PRIORITY, SCOPE_KINDS, STRATEGY, dayOf, hours, type Posting, type RoutingRule } from "@/lib/helpdesk";
import type { AgentsData, QueuesData, RoutingData, Structure } from "./page";

type Tab = "agents" | "queues" | "routing";
interface PostDraft { capabilities: string[]; personId: string; queueCode: string; scopeKind: string; scopeRef: string; isPrimary: boolean; availability: string; effectiveFrom: string; effectiveTo: string; reason: string }
interface QueueDraft { isNew: boolean; code: string; name: string; description: string; officeCode: string; ordinal: string; active: boolean }
interface RuleDraft { id: string | null; categoryCode: string; facultyCode: string; departmentCode: string; queueCode: string; strategy: string; priorityFloor: string; active: boolean }

export function Agents({ tab, agents, queues, routing, structure }: { tab: string; agents: AgentsData; queues: QueuesData; routing: RoutingData; structure: Structure }) {
  const go = useQueryNav();
  const router = useRouter();
  const [busy, setBusy] = useState(false);
  const [problem, setProblem] = useState<Problem | null>(null);
  const [showEnded, setShowEnded] = useState(false);
  const [post, setPost] = useState<PostDraft | null>(null);
  const [qd, setQd] = useState<QueueDraft | null>(null);
  const [rd, setRd] = useState<RuleDraft | null>(null);
  const [off, setOff] = useState<{ personId: string; name: string } | null>(null);
  const [move, setMove] = useState<{ personId: string; name: string; to: string } | null>(null);
  const [reason, setReason] = useState("");
  const n = (v: number | null | undefined) => Number(v ?? 0);

  async function call(method: "POST" | "PUT", path: string, body: unknown, why: string): Promise<boolean> {
    setBusy(true); setProblem(null);
    try {
      const r = await fetch(`/api/bff/api/v1/helpdesk/admin${path}`, { method, headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(why) }, body: JSON.stringify(body) });
      if (!r.ok) { const p = (await r.json().catch(() => null)) ?? { status: r.status, title: r.statusText }; setProblem(p); notifyProblem(p); return false; }
      notify(why);
      router.refresh();
      return true;
    } finally { setBusy(false); }
  }

  const live = agents.postings.filter((p) => p.active);
  const ended = agents.postings.filter((p) => !p.active);
  const people = new Set(live.map((p) => p.person_id)).size;
  const available = new Set(live.filter((p) => p.availability === "AVAILABLE" || p.availability === "BUSY").map((p) => p.person_id)).size;
  const starved = queues.queues.filter((q) => q.active && !n(q.available_agents) && n(q.open));
  const unposted = agents.candidates.filter((c) => !n(c.postings));
  const faculties = structure.faculties;
  const departments = structure.faculties.flatMap((f) => f.departments.map((d) => ({ ...d, faculty: f.name })));
  const scopeName = (p: Posting) => (p.scope_kind === "GLOBAL" ? "The University" : `${SCOPE_KINDS[p.scope_kind] ?? p.scope_kind}: ${p.scope_name ?? p.scope_ref}`);

  const newPost = () => setPost({ capabilities: [], personId: "", queueCode: queues.queues.find((q) => q.active)?.code ?? "", scopeKind: "GLOBAL", scopeRef: "", isPrimary: false, availability: "AVAILABLE", effectiveFrom: "", effectiveTo: "", reason: "" });
  async function savePost() {
    if (!post) return;
    const who = agents.candidates.find((c) => c.id === post.personId)?.name ?? "the agent";
    const q = queues.queues.find((x) => x.code === post.queueCode)?.name ?? post.queueCode;
    if (await call("POST", "/agents", { capabilities: post.capabilities, personId: post.personId, queueCode: post.queueCode, scopeKind: post.scopeKind, scopeRef: post.scopeKind === "GLOBAL" ? null : post.scopeRef.trim(), isPrimary: post.isPrimary, availability: post.availability, effectiveFrom: post.effectiveFrom || null, effectiveTo: post.effectiveTo || null, reason: post.reason.trim() || null },
      `${who} posted on ${q}`)) setPost(null);
  }
  const newQueue = () => setQd({ isNew: true, code: "", name: "", description: "", officeCode: "", ordinal: "100", active: true });
  const editQueue = (q: QueuesData["queues"][number]) => setQd({ isNew: false, code: q.code, name: q.name, description: q.description ?? "", officeCode: q.office_code ?? "", ordinal: String(q.ordinal ?? 100), active: q.active });
  async function saveQueue() {
    if (!qd) return;
    const body = { code: qd.code.trim() || undefined, name: qd.name.trim(), description: qd.description.trim() || null, officeCode: qd.officeCode || null, ordinal: Number(qd.ordinal) || 100, active: qd.active };
    if (await (qd.isNew ? call("POST", "/queues", body, `Queue ${qd.name.trim()} created`) : call("PUT", `/queues/${qd.code}`, body, `Queue ${qd.name.trim()} saved`))) setQd(null);
  }
  const newRule = () => setRd({ id: null, categoryCode: routing.unrouted[0]?.code ?? routing.categories[0]?.code ?? "", facultyCode: "", departmentCode: "", queueCode: routing.queues.find((q) => q.active)?.code ?? "", strategy: "FACULTY_AGENT_FIRST", priorityFloor: "", active: true });
  const editRule = (r: RoutingRule) => setRd({ id: r.id, categoryCode: r.category_code, facultyCode: r.faculty_code ?? "", departmentCode: r.department_code ?? "", queueCode: r.queue_code, strategy: r.strategy, priorityFloor: r.priority_floor ?? "", active: r.active });
  async function saveRule() {
    if (!rd) return;
    const body = { categoryCode: rd.categoryCode, facultyCode: rd.facultyCode || null, departmentCode: rd.departmentCode || null, queueCode: rd.queueCode, strategy: rd.strategy, priorityFloor: rd.priorityFloor || null, active: rd.active };
    const label = `${routing.categories.find((c) => c.code === rd.categoryCode)?.name ?? rd.categoryCode} → ${routing.queues.find((q) => q.code === rd.queueCode)?.name ?? rd.queueCode}`;
    if (await (rd.id ? call("PUT", `/routing/${rd.id}`, body, `Routing rule ${label} saved`) : call("POST", "/routing", body, `Routing rule ${label} created`))) setRd(null);
  }

  const postingRow = (p: Posting) => [
    <span key="a"><strong>{p.name}</strong><div className="sub2 tnum">{p.staff_number ?? ""}{p.left_the_university ? " · left the University" : !p.holds_office ? " · no longer holds the agent office" : ""}</div></span>,
    <span key="q">{p.queue}</span>,
    <span key="s">{scopeName(p)}{p.is_primary ? <> <Pil kind="info">Primary</Pil></> : null}</span>,
    <span key="v">{p.active ? (
      <select className="ctl" value={p.availability} disabled={busy} aria-label={`Availability of ${p.name}`} onChange={(e) => void call("PUT", `/agents/${p.id}`, { availability: e.target.value }, `${p.name}: ${AVAILABILITY[e.target.value]?.[0] ?? e.target.value} on ${p.queue}`)}>
        {Object.entries(AVAILABILITY).map(([k, v]) => <option key={k} value={k}>{v[0]}</option>)}
      </select>
    ) : <Pil kind="grey">Ended</Pil>}</span>,
    <span key="d" className="tnum sub2">{dayOf(p.effective_from)}{p.effective_to ? ` – ${dayOf(p.effective_to)}` : ""}</span>,
    <span key="o" className="tnum">{n(p.open)}</span>,
    <span key="b" className="sub2">{p.assigned_by ?? "—"}{p.reason ? <div>{p.reason}</div> : null}</span>,
    <span key="x" className="row row--inline row--tight row--right">
      {p.active ? <Btn kind="ghost" size="sm" disabled={busy} onClick={() => { if (window.confirm(`End ${p.name}'s posting on ${p.queue}? Any open ticket they hold through it returns to the queue if no other posting keeps them available.`)) void call("PUT", `/agents/${p.id}`, { active: false, reason: "Posting ended by the Head of ICT Support Desk" }, `${p.name}: posting on ${p.queue} ended`); }}>End Posting</Btn> : null}
    </span>,
  ];

  return (
    <>
      <PageHead title="Support Agents, Queues and Routing" description="Who works which queue within what scope; the queues and the office each answers to; where each category of problem goes."
        actions={<>
          {tab === "agents" ? <Btn kind="primary" onClick={newPost}>Post an Agent</Btn> : tab === "queues" ? <Btn kind="primary" onClick={newQueue}>New Queue</Btn> : <Btn kind="primary" onClick={newRule}>New Routing Rule</Btn>}
          <LinkBtn href="/helpdesk">The Desk</LinkBtn>
        </>} />
      {problem ? <ProblemNotice problem={problem} /> : null}
      <Tabs label="Section" items={[{ id: "agents", label: "Agents", count: live.length }, { id: "queues", label: "Queues", count: queues.queues.filter((q) => q.active).length }, { id: "routing", label: "Routing", count: routing.rules.filter((r) => r.active).length }]}
        value={tab as Tab} onChange={(t) => go(`/helpdesk/agents?tab=${t}`)} />

      {tab === "agents" ? (
        <>
          <Tiles items={[
            ["Agents posted", String(people), null, `${live.length} live posting${live.length === 1 ? "" : "s"}`],
            ["Available now", String(available), available < people ? "var(--amber-ink)" : null, `${people - available} away, offline or on leave`],
            ["Queues without an agent", String(starved.length), starved.length ? "var(--red-ink)" : null, starved.length ? starved.map((q) => q.name).join(", ") : "Every queue with open tickets has an available agent"],
            ["Not yet posted", String(unposted.length), unposted.length ? "var(--amber-ink)" : null, "Hold the agent office; work the whole desk until posted"],
          ]} />
          {starved.length ? <Note kind="bad" title="A queue with open tickets and no available agent">New tickets on {starved.map((q) => q.name).join(", ")} are queued for you to assign by hand. Post an agent to {starved.length === 1 ? "it" : "them"}, or make one available.</Note> : null}
          <Panel title="Postings" right={<label className="row row--tight"><input type="checkbox" className="chk" checked={showEnded} onChange={(e) => setShowEnded(e.target.checked)} /> <span className="sub2">Show ended postings ({ended.length})</span></label>}>
            {live.length || (showEnded && ended.length) ? (
              <DTable pageSize={0} cols={["Agent", "Queue", "Scope", "Availability|mid", "From – to|mid", "Open|mid", "Placed by", "|num"]}
                rows={[...live, ...(showEnded ? ended : [])].map(postingRow)}
                texts={[...live, ...(showEnded ? ended : [])].map((p) => `${p.name} ${p.staff_number ?? ""} ${p.queue} ${scopeName(p)} ${p.availability}`)} />
            ) : <PBody><div className="sub2">Nobody is posted yet. Every agent who holds the ICT Support Agent office works the whole desk as before; post them to a queue within a scope to bound what they see and to let the routing choose them.</div></PBody>}
          </Panel>
          <div className="grid grid--2">
            <Panel title="Workload" right="Open tickets with each agent, the overdue among them, and the pace">
              {agents.workload.length ? (
                <DTable pageSize={0} cols={["Agent", "Queues", "Open|mid", "Waiting|mid", "Overdue|mid", "Critical|mid", "This week|mid", "Avg|mid", "|num"]} rows={agents.workload.map((w) => [
                  <span key="a"><strong>{w.name}</strong><div className="sub2">{w.scopes ?? ""}{w.availability !== "AVAILABLE" ? <> <Pil kind={AVAILABILITY[w.availability]?.[1] ?? "grey"}>{AVAILABILITY[w.availability]?.[0] ?? w.availability}</Pil></> : null}</div></span>,
                  <span key="q" className="sub2">{w.queues ?? "—"}</span>,
                  <span key="o" className="tnum">{n(w.open)}</span>,
                  <span key="w" className="tnum">{n(w.waiting)}</span>,
                  <span key="v" className={`tnum${n(w.overdue) ? " ink-red b600" : ""}`}>{n(w.overdue)}</span>,
                  <span key="c" className={`tnum${n(w.critical) ? " ink-red" : ""}`}>{n(w.critical)}</span>,
                  <span key="r" className="tnum">{n(w.resolved_week)}</span>,
                  <span key="h" className="tnum sub2">{hours(w.avg_resolution_hours)}</span>,
                  <span key="x" className="row row--inline row--tight row--right">
                    <LinkBtn size="sm" href={`/helpdesk?agent=${w.person_id}`}>Tickets</LinkBtn>
                    {n(w.open) ? <Btn kind="ghost" size="sm" disabled={busy} onClick={() => { setReason(""); setMove({ personId: w.person_id, name: w.name, to: "" }); }}>Move Open</Btn> : null}
                    <Btn kind="ghost" size="sm" disabled={busy} onClick={() => { setReason(""); setOff({ personId: w.person_id, name: w.name }); }}>Take Off the Desk</Btn>
                  </span>,
                ])} />
              ) : <PBody><div className="sub2">No agent holds a ticket yet.</div></PBody>}
            </Panel>
            <Panel title="Hold the agent office" right="Granted under Users & Roles; posted here">
              <DTable pageSize={0} cols={["Person", "Offices", "Postings|mid", "|num"]} rows={agents.candidates.map((c) => [
                <span key="n"><strong>{c.name}</strong><div className="sub2 tnum">{c.staff_number ?? ""}{c.email ? ` · ${c.email}` : " · no email"}</div></span>,
                <span key="o" className="sub2">{c.offices}</span>,
                <span key="p" className={`tnum${n(c.postings) ? "" : " ink-amber"}`}>{n(c.postings)}</span>,
                <Btn key="x" kind="ghost" size="sm" disabled={busy} onClick={() => { newPost(); setPost((d) => (d ? { ...d, personId: c.id } : d)); }}>Post</Btn>,
              ])} />
              <PBody><div className="sub2">Support access is the office&rsquo;s; a posting only says where and within what scope it is exercised. Someone who does not hold the office cannot be posted — grant the office first.</div></PBody>
            </Panel>
          </div>
        </>
      ) : null}

      {tab === "queues" ? (
        <Panel title="Support queues" right="A queue is deactivated, never deleted; its tickets keep their history">
          <DTable pageSize={0} cols={["Queue", "Code", "Office that decides", "Agents|mid", "Open|mid", "Unassigned|mid", "Waiting|mid", "Overdue|mid", "Resolved this week|mid", "|num"]} rows={queues.queues.map((q) => [
            <span key="n"><strong>{q.name}</strong>{q.active ? null : <> <Pil kind="grey">Inactive</Pil></>}{q.description ? <div className="sub2">{q.description}</div> : null}</span>,
            <span key="c" className="tnum sub2">{q.code}</span>,
            <span key="o">{q.office ?? <span className="sub2">— (only the Director of ICT)</span>}</span>,
            <span key="a" className={`tnum${!n(q.available_agents) && n(q.open) ? " ink-red" : ""}`}>{n(q.available_agents)}<span className="sub2"> of {n(q.agents)}</span></span>,
            <span key="p" className="tnum">{n(q.open)}</span>,
            <span key="u" className={`tnum${n(q.unassigned) ? " ink-amber b600" : ""}`}>{n(q.unassigned)}</span>,
            <span key="w" className="tnum">{n(q.waiting_student) + n(q.waiting_office)}</span>,
            <span key="v" className={`tnum${n(q.overdue) ? " ink-red" : ""}`}>{n(q.overdue)}</span>,
            <span key="r" className="tnum">{n(q.resolved_week)}</span>,
            <span key="x" className="row row--inline row--tight row--right"><LinkBtn size="sm" href={`/helpdesk?queue=${q.code}`}>Tickets</LinkBtn><Btn kind="ghost" size="sm" onClick={() => editQueue(q)}>Edit</Btn></span>,
          ])} />
        </Panel>
      ) : null}

      {tab === "routing" ? (
        <>
          {routing.unrouted.length ? <Note kind="info" title={`${routing.unrouted.length} categor${routing.unrouted.length === 1 ? "y has" : "ies have"} no University-wide rule`}>{routing.unrouted.map((c) => c.name).join(", ")} fall to ICT Support, faculty agent first. Add a rule to send {routing.unrouted.length === 1 ? "it" : "them"} where {routing.unrouted.length === 1 ? "it belongs" : "they belong"}.</Note> : null}
          <Panel title="Routing rules" right="The most specific active rule wins: a department's, then a faculty's, then the University's">
            <DTable pageSize={0} cols={["Category", "Where it applies", "Queue", "Agent chosen by", "Priority at least|mid", "|mid", "|num"]} rows={routing.rules.map((r) => [
              <span key="c"><strong>{r.category}</strong><div className="sub2 tnum">{r.category_code}</div></span>,
              <span key="w">{r.department ? `${r.department} department` : r.faculty ? `${r.faculty}` : "The whole University"}</span>,
              <span key="q">{r.queue}</span>,
              <span key="s">{STRATEGY[r.strategy]?.[0] ?? r.strategy}<div className="sub2">{STRATEGY[r.strategy]?.[1] ?? ""}</div></span>,
              <span key="p">{r.priority_floor ? <Pil kind={PRIORITY[r.priority_floor]?.[1] ?? "grey"}>{PRIORITY[r.priority_floor]?.[0] ?? r.priority_floor}</Pil> : <span className="sub2">as suggested</span>}</span>,
              <span key="a">{r.active ? <Pil kind="ok">Active</Pil> : <Pil kind="grey">Inactive</Pil>}</span>,
              <Btn key="x" kind="ghost" size="sm" onClick={() => editRule(r)}>Edit</Btn>,
            ])} texts={routing.rules.map((r) => `${r.category} ${r.faculty ?? ""} ${r.department ?? ""} ${r.queue} ${r.strategy}`)} />
          </Panel>
        </>
      ) : null}

      {post ? (
        <Modal title="Post an agent on a queue" sub="Within a scope: the University, a faculty, a college, a department or an office. The routing then chooses them for the tickets their posting covers." onClose={() => setPost(null)}
          foot={<><Btn kind="ghost" onClick={() => setPost(null)}>Cancel</Btn><Btn kind="primary" disabled={busy || !post.personId || !post.queueCode || (post.scopeKind !== "GLOBAL" && !post.scopeRef.trim())} onClick={() => void savePost()}>Post the Agent</Btn></>}>
          <div className="stack">
            <Field id="ag-person" label="Agent" required hint="Only people who hold the ICT Support Agent office are listed">
              <select id="ag-person" className="ctl" value={post.personId} onChange={(e) => setPost({ ...post, personId: e.target.value })}>
                <option value="">Choose…</option>
                {agents.candidates.map((c) => <option key={c.id} value={c.id}>{c.name}{c.staff_number ? ` · ${c.staff_number}` : ""} · {c.offices}{n(c.postings) ? ` · ${c.postings} posting${n(c.postings) === 1 ? "" : "s"}` : ""}</option>)}
              </select>
            </Field>
            <div className="row">
              <Field id="ag-queue" label="Queue" required style={{ flex: "1 1 220px" }}>
                <select id="ag-queue" className="ctl" value={post.queueCode} onChange={(e) => setPost({ ...post, queueCode: e.target.value })}>
                  {queues.queues.filter((q) => q.active).map((q) => <option key={q.code} value={q.code}>{q.name}</option>)}
                </select>
              </Field>
              <Field id="ag-scope" label="Scope" required style={{ flex: "1 1 160px" }}>
                <select id="ag-scope" className="ctl" value={post.scopeKind} onChange={(e) => setPost({ ...post, scopeKind: e.target.value, scopeRef: "" })}>
                  {Object.entries(SCOPE_KINDS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
                </select>
              </Field>
              {post.scopeKind === "FACULTY" ? (
                <Field id="ag-ref" label="Faculty" required style={{ flex: "2 1 220px" }}>
                  <select id="ag-ref" className="ctl" value={post.scopeRef} onChange={(e) => setPost({ ...post, scopeRef: e.target.value })}><option value="">Choose…</option>{faculties.map((f) => <option key={f.code} value={f.code}>{f.name}</option>)}</select>
                </Field>
              ) : post.scopeKind === "DEPARTMENT" ? (
                <Field id="ag-ref" label="Department" required style={{ flex: "2 1 220px" }}>
                  <select id="ag-ref" className="ctl" value={post.scopeRef} onChange={(e) => setPost({ ...post, scopeRef: e.target.value })}><option value="">Choose…</option>{departments.map((d) => <option key={d.code} value={d.code}>{d.name} · {d.faculty}</option>)}</select>
                </Field>
              ) : post.scopeKind === "OFFICE" ? (
                <Field id="ag-ref" label="Office" required style={{ flex: "2 1 220px" }}>
                  <select id="ag-ref" className="ctl" value={post.scopeRef} onChange={(e) => setPost({ ...post, scopeRef: e.target.value })}><option value="">Choose…</option>{queues.offices.map((o) => <option key={o.code} value={o.code}>{o.label}</option>)}</select>
                </Field>
              ) : post.scopeKind === "COLLEGE" ? (
                <Field id="ag-ref" label="College" required style={{ flex: "2 1 220px" }}>
                  <select id="ag-ref" className="ctl" value={post.scopeRef} onChange={(e) => setPost({ ...post, scopeRef: e.target.value })}><option value="">Choose…</option>{(structure.colleges ?? []).map((c) => <option key={c.code} value={c.code}>{c.name}</option>)}</select>
                </Field>
              ) : null}
            </div>
            <div>
              <div className="eyebrow">Student records this posting may work on</div>
              <div className="sub2 mb-1">Nothing by default. Each capability is granted here, counts only for the students this posting&rsquo;s scope covers, and is enforced by the server on every call; results, grades, refunds, fees, amounts, matriculation and admission decisions are never among them.</div>
              {Object.entries(CAPABILITIES).map(([code, [label, hint]]) => (
                <label key={code} className="row row--tight" style={{ cursor: "pointer", alignItems: "flex-start", marginBottom: 4 }}>
                  <input type="checkbox" className="chk" checked={post.capabilities.includes(code)} onChange={(e) => setPost({ ...post, capabilities: e.target.checked ? [...post.capabilities, code] : post.capabilities.filter((c) => c !== code) })} />
                  <span><b>{label}</b><div className="sub2">{hint}</div></span>
                </label>
              ))}
            </div>
            <div className="row">
              <Field id="ag-av" label="Availability" style={{ flex: "1 1 150px" }}>
                <select id="ag-av" className="ctl" value={post.availability} onChange={(e) => setPost({ ...post, availability: e.target.value })}>{Object.entries(AVAILABILITY).map(([k, v]) => <option key={k} value={k}>{v[0]}</option>)}</select>
              </Field>
              <Field id="ag-from" label="From" hint="Today if blank" style={{ flex: "1 1 150px" }}><input id="ag-from" className="ctl" type="date" value={post.effectiveFrom} onChange={(e) => setPost({ ...post, effectiveFrom: e.target.value })} /></Field>
              <Field id="ag-to" label="To" hint="Open-ended if blank" style={{ flex: "1 1 150px" }}><input id="ag-to" className="ctl" type="date" value={post.effectiveTo} onChange={(e) => setPost({ ...post, effectiveTo: e.target.value })} /></Field>
              <label className="row row--tight" style={{ alignSelf: "flex-end" }}><input type="checkbox" className="chk" checked={post.isPrimary} onChange={(e) => setPost({ ...post, isPrimary: e.target.checked })} /> <span className="sub2">Primary posting</span></label>
            </div>
            <Field id="ag-reason" label="Note" hint="Optional; kept on the posting"><input id="ag-reason" className="ctl" value={post.reason} onChange={(e) => setPost({ ...post, reason: e.target.value })} maxLength={500} /></Field>
          </div>
        </Modal>
      ) : null}

      {off ? (
        <Modal title={`Take ${off.name} off the desk`} sub="Every posting ends today; every open ticket they hold returns to its queue with no agent, on the record; you are told" onClose={() => setOff(null)}
          foot={<><Btn kind="ghost" onClick={() => setOff(null)}>Cancel</Btn><Btn kind="urgent" disabled={busy || reason.trim().length < 5} onClick={async () => { if (await call("POST", `/agents/${off.personId}/deactivate`, { reason: reason.trim() }, `${off.name} taken off the desk`)) setOff(null); }}>Take Off the Desk</Btn></>}>
          <Field id="ag-off-reason" label="Why" required><textarea id="ag-off-reason" className="ctl" rows={3} value={reason} onChange={(e) => setReason(e.target.value)} maxLength={500} /></Field>
        </Modal>
      ) : null}
      {move ? (
        <Modal title={`Move ${move.name}'s open tickets`} sub="Every open ticket with them goes to another agent, on a reason; the new agent is told" onClose={() => setMove(null)}
          foot={<><Btn kind="ghost" onClick={() => setMove(null)}>Cancel</Btn><Btn kind="primary" disabled={busy || !move.to || move.to === move.personId || reason.trim().length < 5} onClick={async () => { if (await call("POST", `/agents/${move.personId}/reassign`, { toPersonId: move.to, reason: reason.trim() }, `${move.name}'s open tickets moved`)) setMove(null); }}>Move the Tickets</Btn></>}>
          <div className="stack">
            <Field id="ag-move-to" label="To" required>
              <select id="ag-move-to" className="ctl" value={move.to} onChange={(e) => setMove({ ...move, to: e.target.value })}>
                <option value="">Choose…</option>
                {agents.candidates.filter((c) => c.id !== move.personId).map((c) => <option key={c.id} value={c.id}>{c.name} · {c.offices}</option>)}
              </select>
            </Field>
            <Field id="ag-move-reason" label="Why" required><textarea id="ag-move-reason" className="ctl" rows={3} value={reason} onChange={(e) => setReason(e.target.value)} maxLength={500} /></Field>
          </div>
        </Modal>
      ) : null}

      {qd ? (
        <Modal title={qd.isNew ? "New support queue" : `Edit ${qd.name}`} sub="The office that decides is where a ticket of this queue is escalated when support cannot settle it" onClose={() => setQd(null)}
          foot={<><Btn kind="ghost" onClick={() => setQd(null)}>Cancel</Btn><Btn kind="primary" disabled={busy || qd.name.trim().length < 3} onClick={() => void saveQueue()}>{qd.isNew ? "Create the Queue" : "Save"}</Btn></>}>
          <div className="stack">
            <div className="row">
              <Field id="q-name" label="Name" required style={{ flex: "2 1 220px" }}><input id="q-name" className="ctl" value={qd.name} onChange={(e) => setQd({ ...qd, name: e.target.value })} maxLength={120} /></Field>
              <Field id="q-code" label="Code" hint={qd.isNew ? "From the name if blank" : "Fixed"} style={{ flex: "1 1 160px" }}><input id="q-code" className="ctl tnum" value={qd.code} disabled={!qd.isNew} onChange={(e) => setQd({ ...qd, code: e.target.value.toUpperCase() })} maxLength={40} /></Field>
            </div>
            <Field id="q-desc" label="What it handles"><input id="q-desc" className="ctl" value={qd.description} onChange={(e) => setQd({ ...qd, description: e.target.value })} maxLength={500} /></Field>
            <div className="row">
              <Field id="q-office" label="Office that decides" style={{ flex: "2 1 220px" }}>
                <select id="q-office" className="ctl" value={qd.officeCode} onChange={(e) => setQd({ ...qd, officeCode: e.target.value })}><option value="">None (only the Director of ICT)</option>{queues.offices.map((o) => <option key={o.code} value={o.code}>{o.label}</option>)}</select>
              </Field>
              <Field id="q-ord" label="Order" style={{ flex: "0 1 100px" }}><input id="q-ord" className="ctl tnum" inputMode="numeric" value={qd.ordinal} onChange={(e) => setQd({ ...qd, ordinal: e.target.value.replace(/[^0-9]/g, "") })} /></Field>
              <label className="row row--tight" style={{ alignSelf: "flex-end" }}><input type="checkbox" className="chk" checked={qd.active} onChange={(e) => setQd({ ...qd, active: e.target.checked })} /> <span className="sub2">Active</span></label>
            </div>
          </div>
        </Modal>
      ) : null}

      {rd ? (
        <Modal title={rd.id ? "Edit the routing rule" : "New routing rule"} sub="A category to a queue, for the University or for one faculty or department; the strategy picks the agent" onClose={() => setRd(null)}
          foot={<><Btn kind="ghost" onClick={() => setRd(null)}>Cancel</Btn><Btn kind="primary" disabled={busy || !rd.categoryCode || !rd.queueCode} onClick={() => void saveRule()}>{rd.id ? "Save" : "Create the Rule"}</Btn></>}>
          <div className="stack">
            <div className="row">
              <Field id="r-cat" label="Category" required style={{ flex: "1 1 200px" }}>
                <select id="r-cat" className="ctl" value={rd.categoryCode} onChange={(e) => setRd({ ...rd, categoryCode: e.target.value })}>{routing.categories.map((c) => <option key={c.code} value={c.code}>{c.name}{c.active ? "" : " (inactive)"}</option>)}</select>
              </Field>
              <Field id="r-queue" label="Queue" required style={{ flex: "1 1 200px" }}>
                <select id="r-queue" className="ctl" value={rd.queueCode} onChange={(e) => setRd({ ...rd, queueCode: e.target.value })}>{routing.queues.filter((q) => q.active || q.code === rd.queueCode).map((q) => <option key={q.code} value={q.code}>{q.name}</option>)}</select>
              </Field>
            </div>
            <div className="row">
              <Field id="r-fac" label="Only for a faculty" hint="Blank: the whole University" style={{ flex: "1 1 200px" }}>
                <select id="r-fac" className="ctl" value={rd.facultyCode} onChange={(e) => setRd({ ...rd, facultyCode: e.target.value, departmentCode: "" })}><option value="">Any faculty</option>{faculties.map((f) => <option key={f.code} value={f.code}>{f.name}</option>)}</select>
              </Field>
              <Field id="r-dep" label="Only for a department" style={{ flex: "1 1 200px" }}>
                <select id="r-dep" className="ctl" value={rd.departmentCode} onChange={(e) => setRd({ ...rd, departmentCode: e.target.value })}><option value="">Any department</option>{departments.filter((d) => !rd.facultyCode || d.facultyCode === rd.facultyCode).map((d) => <option key={d.code} value={d.code}>{d.name}</option>)}</select>
              </Field>
            </div>
            <div className="row">
              <Field id="r-strat" label="Agent chosen by" required style={{ flex: "2 1 240px" }}>
                <select id="r-strat" className="ctl" value={rd.strategy} onChange={(e) => setRd({ ...rd, strategy: e.target.value })}>{Object.entries(STRATEGY).map(([k, v]) => <option key={k} value={k}>{v[0]}</option>)}</select>
              </Field>
              <Field id="r-floor" label="Priority at least" hint="Raises a lower suggested priority" style={{ flex: "1 1 160px" }}>
                <select id="r-floor" className="ctl" value={rd.priorityFloor} onChange={(e) => setRd({ ...rd, priorityFloor: e.target.value })}><option value="">As the category suggests</option>{Object.entries(PRIORITY).map(([k, v]) => <option key={k} value={k}>{v[0]}</option>)}</select>
              </Field>
              <label className="row row--tight" style={{ alignSelf: "flex-end" }}><input type="checkbox" className="chk" checked={rd.active} onChange={(e) => setRd({ ...rd, active: e.target.checked })} /> <span className="sub2">Active</span></label>
            </div>
            <div className="sub2">{STRATEGY[rd.strategy]?.[1]}</div>
          </div>
        </Modal>
      ) : null}
    </>
  );
}
