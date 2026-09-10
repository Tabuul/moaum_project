"use client";

/** tSecurity — security posture read from the record: the audit spine (entries, shards,
 *  and that every state table is attached to it) and the sign-in defence (attempts by
 *  outcome, and the accounts drawing failed attempts). Nothing here is a claim the system
 *  cannot substantiate from its own data. */
import { Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

export interface Posture {
  audit: { entries: number; shards: number; unattached_tables: number; last_entry: string | null };
  signins: { signed_in: number; bad_password: number; unknown_user: number; locked: number; total: number };
  topFailures: { username: string; attempts: number; last_at: string }[];
}

function when(ts: string | null): string {
  if (!ts) return "—";
  return new Date(ts).toLocaleString("en-GB", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });
}

export function Security({ p }: { p: Posture }) {
  const a = p.audit;
  const s = p.signins;
  const failed = Number(s.bad_password) + Number(s.unknown_user) + Number(s.locked);

  return (
    <>
      <Note kind={Number(a.unattached_tables) === 0 ? "ok" : "bad"} title={Number(a.unattached_tables) === 0 ? "Every state table is on the audit spine" : `${a.unattached_tables} state table(s) not attached to the audit spine`}>
        Security here is what the system can prove from its own record: the tamper-evident audit chain, and the sign-in defence. Infrastructure controls that live below the application — network, host hardening, the WAF — are governed separately and are not asserted on this screen.
      </Note>
      <Tiles items={[
        ["Audit entries", Number(a.entries).toLocaleString(), null, `${a.shards} chain shard${Number(a.shards) === 1 ? "" : "s"}`],
        ["Unattached tables", String(a.unattached_tables), Number(a.unattached_tables) ? "var(--red-ink)" : "var(--green-ink)", Number(a.unattached_tables) ? "A state change could go unrecorded" : "All state is recorded"],
        ["Failed sign-ins, 7 days", String(failed), failed ? "var(--chrome)" : null, `${s.locked} lock-out${Number(s.locked) === 1 ? "" : "s"}`],
        ["Last audit entry", when(a.last_entry), null, "The chain is written on every change"],
      ]} />

      <Panel title="The audit spine" right="Hash-chained, verified nightly across every shard">
        <PBody>
          <div className="sub2">
            The audit chain holds <b>{Number(a.entries).toLocaleString()}</b> entries across <b>{a.shards}</b> shard{Number(a.shards) === 1 ? "" : "s"};
            {Number(a.unattached_tables) === 0 ? " every table that holds state is attached to it, so no state change escapes the record." : ` ${a.unattached_tables} table(s) are not yet attached.`}
            {" "}A nightly job recomputes the chain and reports any break to the Registrar and the Directorate of ICT — not to ICT alone. No application role can write to, forge or amend an audit row.
          </div>
        </PBody>
      </Panel>

      <Panel title="Sign-in defence" right="Last 7 days">
        <DTable cols={["Outcome", "Count|num"]} rows={[
          [<span key="a"><Pil kind="ok">Signed in</Pil></span>, <span className="tnum" key="c">{Number(s.signed_in).toLocaleString()}</span>],
          [<span key="a"><Pil kind="warn">Wrong password</Pil></span>, <span className="tnum" key="c">{Number(s.bad_password).toLocaleString()}</span>],
          [<span key="a"><Pil kind="grey">Unknown username</Pil></span>, <span className="tnum" key="c">{Number(s.unknown_user).toLocaleString()}</span>],
          [<span key="a"><Pil kind="bad">Locked out</Pil></span>, <span className="tnum" key="c">{Number(s.locked).toLocaleString()}</span>],
        ]} />
        <PBody><div className="sub2">Five failed attempts lock an account for fifteen minutes; privileged accounts complete a second step when single sign-on is connected.</div></PBody>
      </Panel>

      <Panel title="Accounts drawing failed attempts" right="Where a lock-out or a guessing attempt is concentrated">
        {p.topFailures.length ? (
          <DTable cols={["Account", "Failed attempts|num", "Last attempt|num"]} rows={p.topFailures.map((r) => [
            <span className="tnum" key="u">{r.username}</span>,
            <b className="tnum" key="a">{r.attempts}</b>,
            <span className="tnum sub2" key="l">{when(r.last_at)}</span>,
          ])} texts={p.topFailures.map((r) => r.username)} />
        ) : <PBody><div className="sub2">No failed sign-in attempts in the last seven days.</div></PBody>}
      </Panel>
    </>
  );
}
