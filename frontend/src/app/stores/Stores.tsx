"use client";

/** tStores — consumable inventory and the fixed-asset register. Each asset carries the
 *  date it was last physically verified, which is what the audit directorate reads. */
import { useState } from "react";
import { useRouter } from "next/navigation";
import type { Problem } from "@/lib/api";
import { reasonHeader } from "@/lib/reason";
import { Btn, Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { Field, day, money } from "@/components/proto/blocks";
import { ProblemNotice } from "@/components/ProblemNotice";

export interface StoreItem { id: string; code: string; name: string; unit: string; quantity: number; reorder_level: number | null; location: string | null; note: string | null; low: boolean }
export interface Asset { id: string; tag: string; name: string; category: string | null; location: string | null; acquired_on: string | null; cost: number | null; condition: string; last_verified_on: string | null }

const COND: Record<string, ["ok" | "info" | "bad" | "grey", string]> = { GOOD: ["ok", "Good"], FAIR: ["info", "Fair"], POOR: ["bad", "Poor"], DISPOSED: ["grey", "Disposed"] };
const yearAgo = new Date(Date.now() - 365 * 864e5).toISOString().slice(0, 10);

export function Stores({ items, assets, actingOffice }: { items: StoreItem[]; assets: Asset[]; actingOffice: string | null }) {
  const router = useRouter();
  const may = ["bursar", "super"].includes(actingOffice ?? "");
  const [tab, setTab] = useState<"items" | "assets">("items");
  const [it, setIt] = useState({ code: "", name: "", unit: "", quantity: "", reorderLevel: "", location: "" });
  const [as, setAs] = useState({ tag: "", name: "", category: "", location: "", acquiredOn: "", cost: "" });
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<Problem | null>(null);
  const [said, setSaid] = useState<string | null>(null);

  async function send(path: string, body: unknown, reason: string): Promise<Record<string, unknown> | null> {
    setBusy(true);
    setErr(null);
    try {
      const r = await fetch(`/api/bff/api/v1${path}`, { method: "POST", headers: { "Content-Type": "application/json", "X-Reason": reasonHeader(reason) }, body: JSON.stringify(body ?? {}) });
      const j = await r.json().catch(() => null);
      if (!r.ok) { setErr(j ?? { status: r.status, title: r.statusText }); return null; }
      router.refresh();
      return j as Record<string, unknown>;
    } finally {
      setBusy(false);
    }
  }

  const low = items.filter((i) => i.low).length;
  const staleAssets = assets.filter((a) => a.condition !== "DISPOSED" && (!a.last_verified_on || a.last_verified_on < yearAgo)).length;

  return (
    <>
      {said ? <Note kind="ok" title={said}>On the record.</Note> : null}
      {err ? <ProblemNotice problem={err} /> : null}
      <Tiles items={[
        ["Inventory items", String(items.length), null, "In stores"],
        ["Below reorder", String(low), low ? "var(--red-ink)" : null, "Need restocking"],
        ["Fixed assets", String(assets.length), null, "On the register"],
        ["Not verified in a year", String(staleAssets), staleAssets ? "var(--chrome)" : null, "Due a physical check"],
      ]} />
      <div className="card"><div className="card__body">
        <div className="role-tabs" role="tablist">
          <button type="button" role="tab" aria-selected={tab === "items" ? "true" : "false"} onClick={() => setTab("items")}>Inventory ({items.length})</button>
          <button type="button" role="tab" aria-selected={tab === "assets" ? "true" : "false"} onClick={() => setTab("assets")}>Fixed assets ({assets.length})</button>
        </div>
      </div></div>

      {tab === "items" ? (
        <>
          <Panel title="Inventory">
            {items.length ? (
              <DTable cols={["Code", "Item", "Quantity|num", "Reorder|num", "Location|mid", "Action|num"]} rows={items.map((i) => [
                <span className="tnum" key="c">{i.code}</span>,
                <span key="n">{i.name}{i.low ? <Pil kind="bad" key="l"> low</Pil> : null}</span>,
                <b className="tnum" key="q">{Number(i.quantity)} {i.unit}</b>,
                <span className="tnum sub2" key="r">{i.reorder_level ?? "—"}</span>,
                <span className="sub2" key="loc">{i.location ?? "—"}</span>,
                <span key="ac">{may ? <Btn kind="ghost" disabled={busy} onClick={() => { const d = window.prompt(`Adjust ${i.name} quantity by (e.g. 20 in, -5 out):`); if (d && d.trim()) void send(`/stores/items/${i.id}/adjust`, { delta: Number(d), note: null }, `Adjust ${i.code}`).then((j) => { if (j) setSaid("Stock adjusted"); }); }}>Adjust</Btn> : null}</span>,
              ])} texts={items.map((i) => `${i.code} ${i.name} ${i.location ?? ""}`)} />
            ) : <PBody><div className="sub2">No inventory item recorded.</div></PBody>}
          </Panel>
          {may ? (
            <Panel title="Add an inventory item">
              <PBody>
                <div className="grid grid--3">
                  <Field id="it-code" label="Code"><input id="it-code" className="ctl tnum" value={it.code} onChange={(e) => setIt({ ...it, code: e.target.value })} /></Field>
                  <Field id="it-name" label="Item"><input id="it-name" className="ctl" value={it.name} onChange={(e) => setIt({ ...it, name: e.target.value })} /></Field>
                  <Field id="it-unit" label="Unit" hint="e.g. box, each"><input id="it-unit" className="ctl" value={it.unit} onChange={(e) => setIt({ ...it, unit: e.target.value })} /></Field>
                </div>
                <div className="grid grid--3">
                  <Field id="it-qty" label="Opening quantity"><input id="it-qty" className="ctl tnum" inputMode="decimal" value={it.quantity} onChange={(e) => setIt({ ...it, quantity: e.target.value.replace(/[^0-9.]/g, "") })} /></Field>
                  <Field id="it-reorder" label="Reorder level" hint="Optional"><input id="it-reorder" className="ctl tnum" inputMode="decimal" value={it.reorderLevel} onChange={(e) => setIt({ ...it, reorderLevel: e.target.value.replace(/[^0-9.]/g, "") })} /></Field>
                  <Field id="it-loc" label="Location" hint="Optional"><input id="it-loc" className="ctl" value={it.location} onChange={(e) => setIt({ ...it, location: e.target.value })} /></Field>
                </div>
                <div><Btn kind="primary" disabled={busy || !it.code.trim() || !it.name.trim()} onClick={async () => { const j = await send("/stores/items", { code: it.code.trim(), name: it.name.trim(), unit: it.unit || null, quantity: it.quantity ? Number(it.quantity) : 0, reorderLevel: it.reorderLevel ? Number(it.reorderLevel) : null, location: it.location || null }, `Add item ${it.code.trim()}`); if (j) { setSaid("Item added"); setIt({ code: "", name: "", unit: "", quantity: "", reorderLevel: "", location: "" }); } }}>Add the item</Btn></div>
              </PBody>
            </Panel>
          ) : null}
        </>
      ) : (
        <>
          <Panel title="Fixed-asset register" right="Each carries the date it was last verified">
            {assets.length ? (
              <DTable cols={["Tag", "Asset", "Location|mid", "Cost|num", "Condition|mid", "Last verified|mid", "Action|num"]} rows={assets.map((a) => [
                <span className="tnum" key="t">{a.tag}</span>,
                <Two key="n" a={a.name} b={a.category ?? ""} />,
                <span className="sub2" key="loc">{a.location ?? "—"}</span>,
                <span className="tnum sub2" key="c">{a.cost == null ? "—" : money(Number(a.cost))}</span>,
                <Pil kind={COND[a.condition]?.[0] ?? "grey"} key="cond">{COND[a.condition]?.[1] ?? a.condition}</Pil>,
                <span className="tnum sub2" key="v">{a.last_verified_on ? day(a.last_verified_on) : "Never"}</span>,
                <span key="ac" style={{ display: "inline-flex", gap: 6, flexWrap: "wrap", justifyContent: "flex-end" }}>
                  {may || ["audit", "deputyaudit"].includes(actingOffice ?? "") ? <Btn kind="go" disabled={busy} onClick={() => void send(`/stores/assets/${a.id}/verify`, {}, `Verify ${a.tag}`).then((j) => { if (j) setSaid(`${a.tag} verified today`); })}>Verify</Btn> : null}
                  {may ? <Btn kind="ghost" disabled={busy} onClick={() => { const c = window.prompt("Condition: GOOD, FAIR, POOR, DISPOSED", a.condition); if (c && c.trim()) void send(`/stores/assets/${a.id}/condition`, { condition: c.trim() }, `Set ${a.tag} condition`); }}>Condition</Btn> : null}
                </span>,
              ])} texts={assets.map((a) => `${a.tag} ${a.name} ${a.location ?? ""} ${a.condition}`)} />
            ) : <PBody><div className="sub2">No asset on the register.</div></PBody>}
          </Panel>
          {may ? (
            <Panel title="Add a fixed asset">
              <PBody>
                <div className="grid grid--3">
                  <Field id="as-tag" label="Asset tag"><input id="as-tag" className="ctl tnum" value={as.tag} onChange={(e) => setAs({ ...as, tag: e.target.value })} /></Field>
                  <Field id="as-name" label="Asset"><input id="as-name" className="ctl" value={as.name} onChange={(e) => setAs({ ...as, name: e.target.value })} /></Field>
                  <Field id="as-cat" label="Category" hint="Optional"><input id="as-cat" className="ctl" value={as.category} onChange={(e) => setAs({ ...as, category: e.target.value })} /></Field>
                </div>
                <div className="grid grid--3">
                  <Field id="as-loc" label="Location" hint="Optional"><input id="as-loc" className="ctl" value={as.location} onChange={(e) => setAs({ ...as, location: e.target.value })} /></Field>
                  <Field id="as-acq" label="Acquired on" hint="Optional"><input id="as-acq" className="ctl" type="date" value={as.acquiredOn} onChange={(e) => setAs({ ...as, acquiredOn: e.target.value })} /></Field>
                  <Field id="as-cost" label="Cost (₦)" hint="Optional"><input id="as-cost" className="ctl tnum" inputMode="decimal" value={as.cost} onChange={(e) => setAs({ ...as, cost: e.target.value.replace(/[^0-9.]/g, "") })} /></Field>
                </div>
                <div><Btn kind="primary" disabled={busy || !as.tag.trim() || !as.name.trim()} onClick={async () => { const j = await send("/stores/assets", { tag: as.tag.trim(), name: as.name.trim(), category: as.category || null, location: as.location || null, acquiredOn: as.acquiredOn || null, cost: as.cost ? Number(as.cost) : null }, `Add asset ${as.tag.trim()}`); if (j) { setSaid("Asset added"); setAs({ tag: "", name: "", category: "", location: "", acquiredOn: "", cost: "" }); } }}>Add the asset</Btn></div>
              </PBody>
            </Panel>
          ) : null}
        </>
      )}
    </>
  );
}
