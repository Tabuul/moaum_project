"use client";
/** The Director's reports (V251): real counts from the tickets, filtered by date, category, priority, agent, faculty and
 *  department; the monthly volume as bars; each breakdown as a table with a meter; the whole downloadable. */
import { useQueryNav } from "@/lib/query-nav";
import { csv, download } from "@/lib/results";
import { Btn, LinkBtn, PageHead, Panel, PBody, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { PRIORITY, STATUS, hours, type Agent, type Category } from "@/lib/helpdesk";
import type { Stats } from "../Desk";

interface Filters { from: string; to: string; category: string; priority: string; agent: string; faculty: string; department: string }

export function Reports({ stats, categories, agents, faculties, departments, filters }: {
  stats: Stats; categories: Category[]; agents: Agent[]; faculties: { code: string; name: string }[]; departments: { code: string; name: string; faculty_code?: string }[]; filters: Filters;
}) {
  const go = useQueryNav();
  const n = (v: number | null | undefined) => Number(v ?? 0);
  const t = stats.totals;
  const nav = (patch: Partial<Filters>) => {
    const next = { ...filters, ...patch };
    const qs = new URLSearchParams();
    for (const [k, v] of Object.entries(next)) if (v) qs.set(k, v);
    go(`/helpdesk/reports${qs.toString() ? "?" + qs.toString() : ""}`);
  };
  const filtered = Object.values(filters).some(Boolean);
  const scope = [filters.from || filters.to ? `${filters.from || "the start"} to ${filters.to || "today"}` : "All time", filters.category ? categories.find((c) => c.code === filters.category)?.name : null, filters.priority ? PRIORITY[filters.priority]?.[0] + " priority" : null, filters.agent ? agents.find((a) => a.id === filters.agent)?.name : null, filters.faculty ? faculties.find((f) => f.code === filters.faculty)?.name : null, filters.department ? departments.find((d) => d.code === filters.department)?.name : null].filter(Boolean).join(" · ");
  const maxMonth = Math.max(1, ...stats.monthly.map((m) => Math.max(n(m.created), n(m.resolved))));

  function breakdown(title: string, rows: { key: string; n: number }[], extra?: (r: { key: string; n: number }) => string) {
    const max = Math.max(1, ...rows.map((r) => n(r.n)));
    const total = rows.reduce((a, r) => a + n(r.n), 0);
    return (
      <Panel title={title} right={`${total} ticket${total === 1 ? "" : "s"}`}>
        {rows.length ? (
          <DTable cols={["", "Tickets|mid", "Share|mid", ""]} rows={rows.map((r, i) => [
            <span key={"k" + i}>{r.key}{extra ? <div className="sub2">{extra(r)}</div> : null}</span>,
            <span key={"n" + i} className="tnum">{n(r.n)}</span>,
            <span key={"s" + i} className="tnum sub2">{total ? Math.round((100 * n(r.n)) / total) : 0}%</span>,
            <span key={"b" + i} className="meter"><span className="meter__bar"><span className="meter__fill" style={{ width: `${Math.round((100 * n(r.n)) / max)}%` }} /></span></span>,
          ])} />
        ) : <PBody><div className="sub2">Nothing in this scope.</div></PBody>}
      </Panel>
    );
  }

  function downloadAll() {
    const rows: (string | number | null)[][] = [["Report", "Item", "Tickets", "Open", "Done", "Overdue", "Average resolution (h)"]];
    for (const r of stats.byStatus) rows.push(["By status", STATUS[r.key]?.[0] ?? r.key, n(r.n), null, null, null, null]);
    for (const r of stats.byCategory) rows.push(["By category", r.key, n(r.n), n(r.open), null, null, null]);
    for (const r of stats.byPriority) rows.push(["By priority", PRIORITY[r.key]?.[0] ?? r.key, n(r.n), null, null, null, null]);
    for (const r of stats.byFaculty) rows.push(["By faculty", r.key, n(r.n), null, null, null, null]);
    for (const r of stats.byDepartment) rows.push(["By department", r.key, n(r.n), null, null, null, null]);
    for (const r of stats.byRequesterKind) rows.push(["By requester", r.key === "STUDENT" ? "Students" : "Staff", n(r.n), null, null, null, null]);
    for (const r of stats.byAgent) rows.push(["By agent", r.key, n(r.n), n(r.open), n(r.done), n(r.overdue), r.avg_resolution_hours == null ? null : Number(r.avg_resolution_hours)]);
    for (const m of stats.monthly) rows.push(["By month", m.key, n(m.created), null, n(m.resolved), null, null]);
    download(`ICT support report ${new Date().toISOString().slice(0, 10)}`, csv(rows, [["Scope", scope], ["Total tickets", String(n(t.total))], ["Open", String(n(t.open))], ["Overdue", String(n(t.overdue))],
      ["Average first response (h)", String(t.avg_first_response_hours ?? "")], ["Average resolution (h)", String(t.avg_resolution_hours ?? "")], ["Average closure (h)", String(t.avg_closure_hours ?? "")]]));
  }

  return (
    <>
      <PageHead title="ICT Support Reports" description="Real figures from the tickets, in the scope you choose. Nothing here is estimated."
        actions={<><Btn kind="primary" onClick={downloadAll}>Download the Report</Btn><LinkBtn href="/helpdesk">The Queue</LinkBtn></>} />
      <div className="filterbar">
        <div className="row">
          <div className="field" style={{ flex: "1 1 140px" }}><label htmlFor="rp-from">Raised from</label><input id="rp-from" className="ctl" type="date" value={filters.from} onChange={(e) => nav({ from: e.target.value })} /></div>
          <div className="field" style={{ flex: "1 1 140px" }}><label htmlFor="rp-to">To</label><input id="rp-to" className="ctl" type="date" value={filters.to} onChange={(e) => nav({ to: e.target.value })} /></div>
          <div className="field" style={{ flex: "1 1 160px" }}><label htmlFor="rp-cat">Category</label><select id="rp-cat" className="ctl" value={filters.category} onChange={(e) => nav({ category: e.target.value })}><option value="">Any</option>{categories.map((c) => <option key={c.code} value={c.code}>{c.name}</option>)}</select></div>
          <div className="field" style={{ flex: "1 1 120px" }}><label htmlFor="rp-pri">Priority</label><select id="rp-pri" className="ctl" value={filters.priority} onChange={(e) => nav({ priority: e.target.value })}><option value="">Any</option>{Object.entries(PRIORITY).map(([k, v]) => <option key={k} value={k}>{v[0]}</option>)}</select></div>
          <div className="field" style={{ flex: "1 1 160px" }}><label htmlFor="rp-agent">Agent</label><select id="rp-agent" className="ctl" value={filters.agent} onChange={(e) => nav({ agent: e.target.value })}><option value="">Any</option>{agents.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}</select></div>
          <div className="field" style={{ flex: "1 1 180px" }}><label htmlFor="rp-fac">Faculty</label><select id="rp-fac" className="ctl" value={filters.faculty} onChange={(e) => nav({ faculty: e.target.value, department: "" })}><option value="">Any</option>{faculties.map((f) => <option key={f.code} value={f.code}>{f.name}</option>)}</select></div>
          <div className="field" style={{ flex: "1 1 180px" }}><label htmlFor="rp-dep">Department</label><select id="rp-dep" className="ctl" value={filters.department} onChange={(e) => nav({ department: e.target.value })}><option value="">Any</option>{departments.filter((d) => !filters.faculty || d.faculty_code === filters.faculty).map((d) => <option key={d.code} value={d.code}>{d.name}</option>)}</select></div>
          {filtered ? <div className="field"><label>&nbsp;</label><Btn kind="ghost" onClick={() => go("/helpdesk/reports")}>Clear</Btn></div> : null}
        </div>
        <div className="sub2 mt-2">Scope: {scope}</div>
      </div>

      <Tiles items={[
        ["Tickets", String(n(t.total)), null, `${n(t.open)} open · ${n(t.resolved)} resolved · ${n(t.closed)} closed`],
        ["Overdue", String(n(t.overdue)), n(t.overdue) ? "var(--red-ink)" : null, `${n(t.response_overdue)} past first response · ${n(t.unassigned)} unassigned`],
        ["Average first response", hours(t.avg_first_response_hours), null, "From submission to the desk's first word"],
        ["Average resolution", hours(t.avg_resolution_hours), null, `Closure ${hours(t.avg_closure_hours)} · ${n(t.ever_resolved) ? Math.round((100 * n(t.resolved_in_sla)) / n(t.ever_resolved)) + "% within SLA" : "no resolutions yet"}`],
      ]} />

      <Panel title="Monthly ticket volume" right="The last twelve months: raised against resolved">
        <PBody>
          <div className="bars">
            {stats.monthly.map((m) => (
              <div key={m.key} className="bars__col" title={`${m.key}: ${n(m.created)} raised, ${n(m.resolved)} resolved, ${n(m.closed)} closed`}>
                <div className="bars__stack">
                  <span className="bars__bar bars__bar--a" style={{ height: `${Math.round((100 * n(m.created)) / maxMonth)}%` }} />
                  <span className="bars__bar bars__bar--b" style={{ height: `${Math.round((100 * n(m.resolved)) / maxMonth)}%` }} />
                </div>
                <div className="bars__label tnum">{new Date(m.key + "-01").toLocaleDateString("en-GB", { month: "short" })}</div>
                <div className="bars__n tnum">{n(m.created)}/{n(m.resolved)}</div>
              </div>
            ))}
          </div>
          <div className="row row--tight sub2 mt-2"><span className="bars__key bars__key--a" /> Raised <span className="bars__key bars__key--b" style={{ marginLeft: 12 }} /> Resolved</div>
        </PBody>
      </Panel>

      <div className="grid grid--2">
        {breakdown("Tickets by status", stats.byStatus.map((r) => ({ key: STATUS[r.key]?.[0] ?? r.key, n: r.n })))}
        {breakdown("Tickets by category", stats.byCategory, (r) => `${n((r as { open?: number }).open)} open`)}
        {breakdown("Tickets by priority", stats.byPriority.map((r) => ({ key: PRIORITY[r.key]?.[0] ?? r.key, n: r.n })))}
        {breakdown("Tickets by requester", stats.byRequesterKind.map((r) => ({ key: r.key === "STUDENT" ? "Students" : "Staff", n: r.n })))}
        {breakdown("Tickets by faculty", stats.byFaculty)}
        {breakdown("Tickets by department", stats.byDepartment)}
      </div>

      <Panel title="Tickets by agent" right="Load, throughput and pace">
        <DTable cols={["Agent", "Tickets|mid", "Open|mid", "Done|mid", "Overdue|mid", "Average resolution|mid"]} rows={stats.byAgent.map((a, i) => [
          <span key={"a" + i} className={a.agent_id ? "" : "sub2"}>{a.key}</span>,
          <span key={"n" + i} className="tnum">{n(a.n)}</span>,
          <span key={"o" + i} className="tnum">{n(a.open)}</span>,
          <span key={"d" + i} className="tnum ink-green">{n(a.done)}</span>,
          <span key={"v" + i} className={`tnum${n(a.overdue) ? " ink-red" : ""}`}>{n(a.overdue)}</span>,
          <span key={"h" + i} className="tnum sub2">{hours(a.avg_resolution_hours)}</span>,
        ])} />
      </Panel>

      <Panel title="The SLA in force" right="Set under Categories and SLAs">
        <DTable cols={["Priority", "First response within|mid", "Resolution within|mid"]} rows={stats.sla.map((s) => [
          <span key="p">{PRIORITY[s.priority]?.[0] ?? s.priority}</span>,
          <span key="f" className="tnum">{hours(s.first_response_hours)}</span>,
          <span key="r" className="tnum">{hours(s.resolution_hours)}</span>,
        ])} />
      </Panel>
    </>
  );
}
