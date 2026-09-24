"use client";

/** tAuditAssets — the audit directorate reads the fixed-asset register, with the date each
 *  asset was last physically verified. An asset not seen in a year is the one to ask about. */
import { day, money } from "@/components/proto/blocks";
import { Note, Panel, PBody, Pil, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

export interface Asset { id: string; tag: string; name: string; category: string | null; location: string | null; acquired_on: string | null; cost: number | null; condition: string; last_verified_on: string | null }

const COND: Record<string, ["ok" | "info" | "bad" | "grey", string]> = { GOOD: ["ok", "Good"], FAIR: ["info", "Fair"], POOR: ["bad", "Poor"], DISPOSED: ["grey", "Disposed"] };
const yearAgo = new Date(Date.now() - 365 * 864e5).toISOString().slice(0, 10);

export function AuditAssets({ rows }: { rows: Asset[] }) {
  const live = rows.filter((a) => a.condition !== "DISPOSED");
  const never = live.filter((a) => !a.last_verified_on).length;
  const stale = live.filter((a) => a.last_verified_on && a.last_verified_on < yearAgo).length;
  const value = live.reduce((n, a) => n + Number(a.cost ?? 0), 0);

  return (
    <>
      <Note kind={never + stale ? "bad" : "ok"} title={never + stale ? `${never + stale} asset(s) not verified within the last year` : "Every live asset has been verified within the year"}>
        The register is the Bursary&rsquo;s; audit reads it. What audit checks is not the value but the <b>verification date</b>: an asset carried on the books that no one has physically seen in a year is where a register and reality drift apart.
      </Note>
      <Tiles items={[
        ["Assets on the register", String(live.length), null, `${rows.length - live.length} disposed`],
        ["Book value", money(value), null, "Live assets with a recorded cost"],
        ["Never verified", String(never), never ? "var(--red-ink)" : null, "No physical check on record"],
        ["Overdue verification", String(stale), stale ? "var(--red-ink)" : null, "Last seen over a year ago"],
      ]} />
      <Panel title="Fixed-asset register" right="With the date each was last physically verified">
        {rows.length ? (
          <DTable cols={["Tag", "Asset", "Location|mid", "Cost|num", "Condition|mid", "Last verified|num"]} rows={rows.map((a) => {
            const overdue = a.condition !== "DISPOSED" && (!a.last_verified_on || a.last_verified_on < yearAgo);
            return [
              <span className="tnum" key="t">{a.tag}</span>,
              <Two key="n" a={a.name} b={a.category ?? ""} />,
              <span className="sub2" key="loc">{a.location ?? "—"}</span>,
              <span className="tnum sub2" key="c">{a.cost == null ? "—" : money(Number(a.cost))}</span>,
              <Pil kind={COND[a.condition]?.[0] ?? "grey"} key="cond">{COND[a.condition]?.[1] ?? a.condition}</Pil>,
              <span className={`tnum${overdue ? " ink-red b600" : ""}`} key="v">{a.last_verified_on ? day(a.last_verified_on) : "Never"}</span>,
            ];
          })} texts={rows.map((a) => `${a.tag} ${a.name} ${a.location ?? ""} ${a.condition}`)} />
        ) : <PBody><div className="sub2">No asset is on the register yet. Assets appear here once the Bursary records them in Stores &amp; assets.</div></PBody>}
      </Panel>
    </>
  );
}
