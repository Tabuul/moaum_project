"use client";

/** iAudit — proto/part…: the audit trail, read over audit.entries. The application holds
 *  insert and select on that store and nothing else, so the trail cannot be edited through
 *  the portal; the rows are hash-chained, so a deletion at database level is detectable. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import { Btn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field } from "@/components/proto/blocks";
import { officeLabel } from "@/lib/offices";

export interface Entry {
  occurred_at: string; actor_id: string; actor_office: string; action: string; subject_type: string;
  subject_id: string; reason: string | null; correlation_id: string | null; actor_name: string | null;
}
/** V627: the people a "who" named (null when none was asked) */
export interface Named { id: string; name: string; kind: "staff" | "student"; number: string | null }
export interface AuditView { tiles: { total: number; today: number; actorsToday: number; refusalsToday: number }; entries: Entry[]; filterWindow?: number; who?: Named[] | null }
/** V627: what the read is limited to, as the URL carries it */
export interface AuditScope { action: string; office: string; from: string; to: string; who: string }
/** V623: the filters and their counts read the latest `window` entries of the trail */
export interface Facets { actions: { domain: string; n: number }[]; offices: { actor_office: string; n: number }[]; window?: number }

function when(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleDateString("en-GB", { day: "2-digit", month: "short" }) + " " + d.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit", second: "2-digit" });
}

export function AuditTrail({ d, facets, scope }: { d: AuditView; facets: Facets; scope: AuditScope }) {
  const router = useRouter();
  const { action, office, from, to, who } = scope;
  const [whoText, setWhoText] = useState(who);
  function go(next: Partial<AuditScope>) {
    const q = new URLSearchParams();
    for (const [k, v] of Object.entries({ ...scope, ...next })) if (v) q.set(k, v);
    router.push(`/audit${q.toString() ? `?${q.toString()}` : ""}`);
  }
  const isRefusal = (x: string) => /refus|denied|blocked/i.test(x);
  const windowWords = (d.filterWindow ?? 50000).toLocaleString();
  const named = d.who ?? null;
  const day = (iso: string) => new Date(`${iso}T12:00:00`).toLocaleDateString("en-GB", { day: "2-digit", month: "short", year: "numeric" });
  const range = from && to ? (from === to ? day(from) : `${day(from)} to ${day(to)}`) : from ? `from ${day(from)}` : to ? `up to ${day(to)}` : "";
  const scoped = Boolean(action || office || from || to || who);
  const heading = [
    `Most recent ${d.entries.length}`,
    named && named.length ? `by ${named.map((n) => n.name).join("; ")}` : "",
    range,
    action || office ? `filtered within the latest ${windowWords} entries` : "",
  ].filter(Boolean).join(" · ");

  return (
    <>
      <Note kind="info" title="The audit trail cannot be edited through the application">
        Every state change, with the person, office and reason. The rows are hash-chained, so a change at database level is detectable.
      </Note>

      <Tiles items={[
        ["Entries on the record", d.tiles.total.toLocaleString(), null, "Since the system began"],
        ["Today", d.tiles.today.toLocaleString(), null, "State changes since midnight"],
        ["Actors today", String(d.tiles.actorsToday), null, "Distinct people and services"],
        ["Refusals today", String(d.tiles.refusalsToday), d.tiles.refusalsToday ? "var(--chrome)" : null, "Changes the rules refused"],
      ]} />

      {/* the filters side by side: .card__body lays its children in a column, so the row is its own element */}
      <div className="card"><div className="card__body"><div className="row row--end">
        <div style={{ minWidth: 150 }}><Field id="au-from" label="From">
          <input id="au-from" type="date" className="ctl" value={from} max={to || undefined} onChange={(e) => go({ from: e.target.value })} />
        </Field></div>
        <div style={{ minWidth: 150 }}><Field id="au-to" label="To">
          <input id="au-to" type="date" className="ctl" value={to} min={from || undefined} onChange={(e) => go({ to: e.target.value })} />
        </Field></div>
        <form className="row row--end" onSubmit={(e) => { e.preventDefault(); go({ who: whoText.trim() }); }}>
          <div style={{ minWidth: 240 }}><Field id="au-who" label="Who">
            <input id="au-who" className="ctl" value={whoText} placeholder="Name, staff or matric number" onChange={(e) => setWhoText(e.target.value)} />
          </Field></div>
          <Btn kind="ghost" type="submit">Find</Btn>
        </form>
        <div style={{ minWidth: 200 }}><Field id="au-action" label="Domain">
          <select id="au-action" className="ctl" value={action} onChange={(e) => go({ action: e.target.value })}>
            <option value="">All actions</option>
            {facets.actions.map((a) => <option key={a.domain} value={a.domain}>{a.domain} ({a.n})</option>)}
          </select></Field></div>
        <div style={{ minWidth: 200 }}><Field id="au-office" label="Acting office">
          <select id="au-office" className="ctl" value={office} onChange={(e) => go({ office: e.target.value })}>
            <option value="">All offices</option>
            {facets.offices.map((o) => <option key={o.actor_office} value={o.actor_office}>{officeLabel(o.actor_office)} ({o.n})</option>)}
          </select></Field></div>
        {scoped ? <Btn kind="ghost" onClick={() => { setWhoText(""); router.push("/audit"); }}>Clear</Btn> : null}
      </div>
        {named && named.length > 1 ? <div className="sub2">“{who}” names {named.length} people: {named.map((n) => `${n.name}${n.number ? ` (${n.number})` : ""}`).join("; ")}. Their entries are shown together.</div> : null}
      </div></div>

      <Panel title="Audit trail" right={heading}>
        {d.entries.length ? (
          <DTable cols={["When|mid", "Actor", "Action", "Subject", "Reason"]} rows={d.entries.map((e, i) => [
            <span className="tnum sub2" key={"w" + i}>{when(e.occurred_at)}</span>,
            <Two key={"a" + i} a={e.actor_name ?? "System"} b={officeLabel(e.actor_office)} />,
            <span key={"ac" + i}>{isRefusal(e.action) ? <Pil kind="bad">{e.action}</Pil> : <span className="tnum sub2">{e.action}</span>}</span>,
            <Two key={"s" + i} a={e.subject_type} b={e.subject_id ? e.subject_id.slice(0, 8) : ""} />,
            <span className="sub2" key={"r" + i}>{e.reason ?? "—"}</span>,
          ])} texts={d.entries.map((e) => `${e.actor_name ?? ""} ${e.action} ${e.subject_type}`)} />
        ) : <PBody><div className="sub2">{named && !named.length ? `No one matches “${who}”.`
          : action || office ? `No entry among the latest ${windowWords} matches this filter.`
          : scoped ? "No entry in this range." : "No entry on the trail yet."}</div></PBody>}
      </Panel>

      <Note kind="info" title="A refusal is as much a record as a success">
        A write the database refused is on the trail with its reason.
      </Note>
    </>
  );
}
