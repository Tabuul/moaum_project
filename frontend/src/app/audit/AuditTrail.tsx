"use client";

/** iAudit — proto/part…: the audit trail, read over audit.entries. The application holds
 *  insert and select on that store and nothing else, so the trail cannot be edited through
 *  the portal; the rows are hash-chained, so a deletion at database level is detectable. */
import { useRouter } from "next/navigation";
import { Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { officeLabel } from "@/lib/offices";

export interface Entry {
  occurred_at: string; actor_id: string; actor_office: string; action: string; subject_type: string;
  subject_id: string; reason: string | null; correlation_id: string | null; actor_name: string | null;
}
export interface AuditView { tiles: { total: number; today: number; actorsToday: number; refusalsToday: number }; entries: Entry[] }
export interface Facets { actions: { domain: string; n: number }[]; offices: { actor_office: string; n: number }[] }

function when(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleDateString("en-GB", { day: "2-digit", month: "short" }) + " " + d.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit", second: "2-digit" });
}

export function AuditTrail({ d, facets, action, office }: { d: AuditView; facets: Facets; action: string; office: string }) {
  const router = useRouter();
  function go(next: { action?: string; office?: string }) {
    const q = new URLSearchParams();
    const a = next.action ?? action;
    const o = next.office ?? office;
    if (a) q.set("action", a);
    if (o) q.set("office", o);
    router.push(`/audit${q.toString() ? `?${q.toString()}` : ""}`);
  }
  const isRefusal = (x: string) => /refus|denied|blocked/i.test(x);

  return (
    <>
      <Note kind="info" title="The audit trail cannot be edited through the application">
        Every state change in the University is written here, against the person and office that made it, with the reason it was made. The application holds insert and select on this store and nothing else; the rows are hash-chained, so a change or deletion at database level is detectable. This screen only reads it.
      </Note>

      <Tiles items={[
        ["Entries on the record", d.tiles.total.toLocaleString(), null, "Since the system began"],
        ["Today", d.tiles.today.toLocaleString(), null, "State changes since midnight"],
        ["Actors today", String(d.tiles.actorsToday), null, "Distinct people and services"],
        ["Refusals today", String(d.tiles.refusalsToday), d.tiles.refusalsToday ? "var(--chrome)" : null, "A rule doing its job"],
      ]} />

      <div className="card"><div className="card__body" style={{ display: "flex", gap: 10, flexWrap: "wrap", alignItems: "flex-end" }}>
        <div className="field" style={{ minWidth: 180 }}><label htmlFor="au-action">Domain</label>
          <select id="au-action" className="ctl" value={action} onChange={(e) => go({ action: e.target.value })}>
            <option value="">All actions</option>
            {facets.actions.map((a) => <option key={a.domain} value={a.domain}>{a.domain} ({a.n})</option>)}
          </select></div>
        <div className="field" style={{ minWidth: 180 }}><label htmlFor="au-office">Acting office</label>
          <select id="au-office" className="ctl" value={office} onChange={(e) => go({ office: e.target.value })}>
            <option value="">All offices</option>
            {facets.offices.map((o) => <option key={o.actor_office} value={o.actor_office}>{officeLabel(o.actor_office)} ({o.n})</option>)}
          </select></div>
        {action || office ? <button className="btn btn--ghost btn--sm" onClick={() => router.push("/audit")}>Clear</button> : null}
      </div></div>

      <Panel title="Audit trail" right={`Most recent ${d.entries.length}${action || office ? " · filtered" : ""}`}>
        {d.entries.length ? (
          <DTable cols={["When|mid", "Actor", "Action", "Subject", "Reason"]} rows={d.entries.map((e, i) => [
            <span className="tnum sub2" key={"w" + i}>{when(e.occurred_at)}</span>,
            <Two key={"a" + i} a={e.actor_name ?? "System"} b={officeLabel(e.actor_office)} />,
            <span key={"ac" + i}>{isRefusal(e.action) ? <Pil kind="bad">{e.action}</Pil> : <span className="tnum sub2">{e.action}</span>}</span>,
            <Two key={"s" + i} a={e.subject_type} b={e.subject_id ? e.subject_id.slice(0, 8) : ""} />,
            <span className="sub2" key={"r" + i}>{e.reason ?? "—"}</span>,
          ])} texts={d.entries.map((e) => `${e.actor_name ?? ""} ${e.action} ${e.subject_type}`)} />
        ) : <PBody><div className="sub2">No entry matches this filter.</div></PBody>}
      </Panel>

      <Note kind="info" title="A refusal is as much a record as a success">
        A write that the database refused — an unattributed change, a second approval by the same person, a mark for a candidate who never registered — is on the trail with its reason, because the attempt is itself a thing worth knowing about.
      </Note>
    </>
  );
}
