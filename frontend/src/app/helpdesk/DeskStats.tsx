"use client";
/** The desk's figures, last and folded (October 2026): the KPI tiles and the breakdowns the desk had at the top since V251,
 *  unchanged in substance, now below the ticket workspace and opened on demand. The choice is remembered on this
 *  browser only. When the figures could not be read, the panel says so and the desk above is unaffected. */
import { useSyncExternalStore } from "react";
import { LinkBtn, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { PRIORITY, hours } from "@/lib/helpdesk";
import Link from "next/link";

export interface Stats {
  totals: { total: number; submitted: number; opened: number; in_progress: number; reopened: number; resolved: number; closed: number; waiting_student?: number; waiting_office?: number; open: number; unassigned: number; high: number; critical?: number; overdue: number; response_overdue: number; escalated: number; avg_first_response_hours: number | null; avg_resolution_hours: number | null; avg_closure_hours: number | null; resolved_in_sla: number; ever_resolved: number; mine_open: number };
  byStatus: { key: string; n: number }[]; byCategory: { key: string; n: number; open: number }[]; byPriority: { key: string; n: number }[];
  byFaculty: { key: string; n: number }[]; byDepartment: { key: string; n: number }[]; byRequesterKind: { key: string; n: number }[];
  byAgent: { key: string; agent_id: string | null; n: number; open: number; done: number; overdue: number; avg_resolution_hours: number | null }[];
  byQueue?: { key: string; queue_code: string | null; n: number; open: number; unassigned: number; waiting: number; overdue: number; avg_resolution_hours: number | null }[];
  monthly: { key: string; created: number; resolved: number; closed: number }[];
  sla: { priority: string; first_response_hours: number; resolution_hours: number }[];
}
const KEY = "moaum.helpdesk.stats-open";
/* the folded-or-open choice: kept on this browser, read as an external store so the server and the first paint agree (folded) */
const listeners = new Set<() => void>();
let remembered: boolean | null = null;
const subscribe = (cb: () => void) => { listeners.add(cb); return () => { listeners.delete(cb); }; };
const readOpen = () => { if (remembered !== null) return remembered; try { return window.localStorage.getItem(KEY) === "1"; } catch { return false; } };
const writeOpen = (v: boolean) => { remembered = v; try { window.localStorage.setItem(KEY, v ? "1" : "0"); } catch { /* not remembered beyond this page, still shown */ } listeners.forEach((l) => l()); };

export function DeskStats({ stats, head }: { stats: Stats | null; head: boolean }) {
  const open = useSyncExternalStore(subscribe, readOpen, () => false);
  const toggle = () => writeOpen(!open);
  const n = (v: number | null | undefined) => Number(v ?? 0);
  const t = stats?.totals;
  return (
    <Panel title="Statistics and analytics" right={<span className="row row--inline row--tight">
      {head ? <LinkBtn href="/helpdesk/reports" size="sm">Reports</LinkBtn> : null}
      <button type="button" className="btn btn--ghost btn--sm" aria-expanded={open} onClick={toggle}>{open ? "Hide statistics" : "Show statistics"}</button>
    </span>}>
      {!open ? (
        <PBody><div className="sub2">{t ? `${n(t.total)} tickets in all · ${n(t.open)} open · ${n(t.resolved)} resolved · ${n(t.closed)} closed · average resolution ${hours(t.avg_resolution_hours)}${n(t.ever_resolved) ? ` · ${Math.round((100 * n(t.resolved_in_sla)) / n(t.ever_resolved))}% within SLA` : ""}` : "Statistics are temporarily unavailable."}</div></PBody>
      ) : !stats || !t ? (
        <PBody><div className="sub2">Statistics are temporarily unavailable. The ticket queue above is unaffected.</div></PBody>
      ) : (
        <PBody>
          <div className="stack">
            <Tiles items={[
              ["Total tickets", String(n(t.total)), null, `${n(t.closed)} closed · ${n(t.resolved)} resolved`],
              ["New", String(n(t.submitted)), n(t.submitted) ? "var(--red-ink)" : null, "Submitted, not yet opened"],
              ["In hand", String(n(t.opened) + n(t.in_progress) + n(t.reopened)), null, `${n(t.opened)} opened · ${n(t.in_progress)} in progress · ${n(t.reopened)} reopened`],
              ["Waiting", String(n(t.waiting_student) + n(t.waiting_office)), null, `${n(t.waiting_student)} on the requester · ${n(t.waiting_office)} on an office`],
            ]} />
            <Tiles items={[
              ["Unassigned", String(n(t.unassigned)), n(t.unassigned) ? "var(--amber-ink)" : null, "Open, with no agent"],
              ["High priority", String(n(t.high)), n(t.high) ? "var(--red-ink)" : null, `${n(t.critical)} critical · high, urgent or critical, still open`],
              ["Overdue", String(n(t.overdue)), n(t.overdue) ? "var(--red-ink)" : null, `${n(t.response_overdue)} past first response · ${n(t.escalated)} escalated`],
              ["Average resolution", hours(t.avg_resolution_hours), null, `First response ${hours(t.avg_first_response_hours)} · ${n(t.ever_resolved) ? Math.round((100 * n(t.resolved_in_sla)) / n(t.ever_resolved)) + "% within SLA" : "no resolutions yet"}`],
            ]} />
            <div className="grid grid--2">
              <div className="stack">
                <div className="b600">Tickets by queue</div>
                {stats.byQueue?.length ? (
                  <DTable pageSize={0} noPrint cols={["Queue", "Open|mid", "Unassigned|mid", "Waiting|mid", "Overdue|mid", "All|mid", "Avg|mid"]} rows={stats.byQueue.map((r, i) => [
                    <span key={"q" + i}>{r.queue_code ? <Link className="lnk" href={`/helpdesk?queue=${r.queue_code}`}>{r.key}</Link> : <span className="sub2">{r.key}</span>}</span>,
                    <span key={"o" + i} className="tnum">{n(r.open)}</span>,
                    <span key={"u" + i} className={`tnum${n(r.unassigned) ? " ink-amber" : ""}`}>{n(r.unassigned)}</span>,
                    <span key={"w" + i} className="tnum">{n(r.waiting)}</span>,
                    <span key={"v" + i} className={`tnum${n(r.overdue) ? " ink-red" : ""}`}>{n(r.overdue)}</span>,
                    <span key={"n" + i} className="tnum">{n(r.n)}</span>,
                    <span key={"h" + i} className="tnum sub2">{hours(r.avg_resolution_hours)}</span>,
                  ])} />
                ) : <div className="sub2">No ticket on a queue yet.</div>}
              </div>
              <div className="stack">
                <div className="b600">Tickets by category</div>
                <DTable pageSize={0} noPrint cols={["Category", "Open|mid", "All|mid", ""]} rows={stats.byCategory.map((c, i) => {
                  const max = Math.max(1, ...stats.byCategory.map((x) => n(x.n)));
                  return [
                    <span key={"c" + i}>{c.key}</span>,
                    <span key={"o" + i} className="tnum">{n(c.open)}</span>,
                    <span key={"n" + i} className="tnum">{n(c.n)}</span>,
                    <span key={"b" + i} className="meter"><span className="meter__bar"><span className="meter__fill" style={{ width: `${Math.round((100 * n(c.n)) / max)}%` }} /></span></span>,
                  ];
                })} />
              </div>
            </div>
            <div className="grid grid--2">
              <div className="stack">
                <div className="b600">Tickets by agent</div>
                <DTable pageSize={0} noPrint cols={["Agent", "Open|mid", "Overdue|mid", "Done|mid", "Avg|mid"]} rows={stats.byAgent.map((a, i) => [
                  <span key={"a" + i}>{a.agent_id ? <Link className="lnk" href={`/helpdesk?agent=${a.agent_id}`}>{a.key}</Link> : <span className="sub2">{a.key}</span>}</span>,
                  <span key={"o" + i} className="tnum">{n(a.open)}</span>,
                  <span key={"v" + i} className={`tnum${n(a.overdue) ? " ink-red" : ""}`}>{n(a.overdue)}</span>,
                  <span key={"d" + i} className="tnum">{n(a.done)}</span>,
                  <span key={"h" + i} className="tnum sub2">{hours(a.avg_resolution_hours)}</span>,
                ])} />
              </div>
              <div className="stack">
                <div className="b600">By faculty, by priority, the SLA</div>
                <div className="row row--base">{stats.byFaculty.slice(0, 8).map((f, i) => <Pil key={i} kind="grey">{f.key} · {n(f.n)}</Pil>)}</div>
                <div className="row row--base">{stats.byPriority.map((p, i) => <Pil key={i} kind={PRIORITY[p.key]?.[1] ?? "grey"}>{PRIORITY[p.key]?.[0] ?? p.key} · {n(p.n)}</Pil>)}</div>
                <div className="sub2">{stats.sla.map((s) => `${PRIORITY[s.priority]?.[0] ?? s.priority}: respond in ${s.first_response_hours} h, resolve in ${s.resolution_hours} h`).join(" · ")}</div>
              </div>
            </div>
          </div>
        </PBody>
      )}
    </Panel>
  );
}
