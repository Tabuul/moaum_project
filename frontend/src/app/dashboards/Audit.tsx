import Link from "next/link";
import type { Me } from "@/components/proto/Shell";
import type { Posture } from "@/app/security/Security";
import { Note, Panel, PBody, Tiles, Two } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

export interface AuditEntry { occurred_at: string; actor_name: string | null; actor_office: string | null; action: string; subject_type: string; reason: string | null }

const when = (ts: string | null) => { if (!ts) return "—"; try { return new Date(ts).toLocaleString("en-GB", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" }); } catch { return "—"; } };

/** The Director of Internal Audit's home: the integrity of the record and a window on recent activity —
 *  the audit spine's own figures and the latest attributed changes and sign-ins (V002). Read-only. */
export function AuditDashboard({ me, posture, feed }: { me: Me | null; posture: Posture | null; feed: AuditEntry[] }) {
  const a = posture?.audit;
  const s = posture?.signins;
  const off = Number(a?.unattached_tables ?? 0);
  const failed = s ? Number(s.bad_password) + Number(s.unknown_user) + Number(s.locked) : 0;
  return (
    <>
      {off ? (
        <Note kind="bad" title={`${off} state table${off === 1 ? " is" : "s are"} not on the audit spine`} action={<Link href="/audit" className="btn btn--urgent btn--sm">Open the audit trail</Link>}>
          A table off the spine can be changed without a record. Everything else here rests on the spine being complete.
        </Note>
      ) : (
        <Note kind="ok" title="The record is complete and hash-chained" action={<Link href="/audit" className="btn btn--primary btn--sm">Open the audit trail</Link>}>
          Every state table is on the spine and each entry is chained to the one before it, so a tampered row is detectable.
        </Note>
      )}

      <Tiles items={[
        ["Audit entries", Number(a?.entries ?? 0).toLocaleString(), null, `${a?.shards ?? 0} shard${Number(a?.shards ?? 0) === 1 ? "" : "s"}`],
        ["Tables off the spine", String(off), off ? "var(--red-ink)" : "var(--green-ink)", off ? "Attributability gap" : "All attached"],
        ["Failed sign-ins", String(failed), failed ? "var(--chrome)" : "var(--green-ink)", `${s?.locked ?? 0} locked out`],
        ["Last entry", when(a?.last_entry ?? null), null, "Most recent attributed change"],
      ]} />

      <Panel title="Recent activity" right={<Link href="/audit" className="btn btn--ghost btn--sm">Full audit trail</Link>}>
        {feed.length ? (
          <DTable cols={["When|mid", "Who", "Action", "On"]}
            rows={feed.slice(0, 12).map((e) => [
              <span className="tnum sub2" key="w">{when(e.occurred_at)}</span>,
              <Two key="a" a={e.actor_name ?? "—"} b={e.actor_office ?? ""} />,
              <span className="tnum" key="c">{e.action}</span>,
              <span className="sub2" key="s">{e.subject_type}{e.reason ? ` · ${e.reason}` : ""}</span>,
            ])} texts={feed.map((e) => `${e.actor_name ?? ""} ${e.action} ${e.subject_type}`)} />
        ) : <PBody><div className="sub2">No recent activity to show. Every attributed change and sign-in appears on the audit trail.</div></PBody>}
      </Panel>

      <Panel title="Oversight desks" right={me?.name ? `Signed in as ${me.name}` : "Internal Audit"}>
        <PBody>
          <div className="grid--fill">
            <Link href="/audit" className="btn btn--ghost btn--sm">Audit trail</Link>
            <Link href="/finance/exceptions" className="btn btn--ghost btn--sm">Finance exceptions</Link>
            <Link href="/finance/reconcile" className="btn btn--ghost btn--sm">Reconciliation</Link>
            <Link href="/people" className="btn btn--ghost btn--sm">Users &amp; roles</Link>
          </div>
        </PBody>
      </Panel>
    </>
  );
}
