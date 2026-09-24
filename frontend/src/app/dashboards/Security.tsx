import type { Me } from "@/components/proto/Shell";
import type { Posture } from "@/app/security/Security";
import { LinkBtn, Note, Panel, PBody, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

const when = (ts: string | null) => { if (!ts) return "—"; try { return new Date(ts).toLocaleString("en-GB", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" }); } catch { return "—"; } };

/** The Chief Security Officer's home: the sign-in defence and the integrity of the record — from the
 *  audit spine and the sign-in events (V002), nothing the system cannot substantiate. */
export function SecurityDashboard({ me, posture }: { me: Me | null; posture: Posture | null }) {
  if (!posture) return <Note kind="bad" title="The security posture could not be read">The dashboard reads the audit spine and the sign-in events; they did not answer.</Note>;
  const a = posture.audit;
  const s = posture.signins;
  const failed = Number(s.bad_password) + Number(s.unknown_user) + Number(s.locked);
  const off = Number(a.unattached_tables);
  const top = posture.topFailures ?? [];
  return (
    <>
      {off ? (
        <Note kind="bad" title={`${off} state table${off === 1 ? " is" : "s are"} not on the audit spine`} action={<LinkBtn kind="urgent" href="/security">Security posture</LinkBtn>}>
          Every state change must be attributable. A table off the spine can be changed without a record — the first thing to close.
        </Note>
      ) : Number(s.locked) ? (
        <Note kind="info" title={`${s.locked} account${Number(s.locked) === 1 ? " is" : "s are"} locked out`} action={<LinkBtn kind="primary" href="/security">Security posture</LinkBtn>}>
          Five failed attempts lock an account for fifteen minutes. The accounts drawing the most failed attempts are below.
        </Note>
      ) : (
        <Note kind="ok" title="The record is whole and sign-ins are healthy" action={<LinkBtn kind="ghost" href="/security">Security posture</LinkBtn>}>
          Every state table is on the audit spine and no account is locked out.
        </Note>
      )}

      <Tiles items={[
        ["Failed sign-ins", String(failed), failed ? "var(--red-ink)" : "var(--green-ink)", `${s.bad_password} bad password · ${s.unknown_user} unknown`],
        ["Locked out", String(s.locked), Number(s.locked) ? "var(--red-ink)" : "var(--green-ink)", "Fifteen-minute lock"],
        ["Audit entries", Number(a.entries).toLocaleString(), null, `${a.shards} shard${Number(a.shards) === 1 ? "" : "s"} · last ${when(a.last_entry)}`],
        ["Tables off the spine", String(off), off ? "var(--red-ink)" : "var(--green-ink)", off ? "Attributability gap" : "All attached"],
      ]} />

      <Panel title="Accounts drawing failed sign-ins" right={top.length ? `${top.length} account${top.length === 1 ? "" : "s"}` : "None"}>
        {top.length ? (
          <DTable cols={["Account", "Failed attempts|mid", "Last attempt|num"]}
            rows={top.slice(0, 12).map((f) => [
              <span className="tnum" key="u">{f.username}</span>,
              <b className="tnum ink-red" key="n">{f.attempts}</b>,
              <span className="tnum sub2" key="l">{when(f.last_at)}</span>,
            ])} texts={top.map((f) => f.username)} />
        ) : <PBody><div className="sub2">No account is drawing failed sign-ins. A run of attempts on one account shows here to be watched.</div></PBody>}
      </Panel>

      <Panel title="Security desks" right={me?.name ? `Signed in as ${me.name}` : "Security"}>
        <PBody>
          <div className="grid--fill">
            <LinkBtn kind="ghost" href="/security">Security posture</LinkBtn>
            <LinkBtn kind="ghost" href="/audit">Audit trail</LinkBtn>
            <LinkBtn kind="ghost" href="/people">Users &amp; roles</LinkBtn>
          </div>
        </PBody>
      </Panel>
    </>
  );
}
