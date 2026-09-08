import { api, API_URL } from "@/lib/api";
import type { Me } from "@/components/proto/Shell";
import { KvGrid, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import { officeLabel } from "@/lib/offices";

interface Status {
  service: string;
  commit?: string;
  startedAt: string;
  database: {
    reachable: boolean;
    migrationsApplied?: number;
    latestMigration?: string;
    admissionSettings2025_2026?: string;
    why?: string;
  };
}

/** the outbox (V025): what waits, what went, and whether a provider is wired at all */
interface Outbox {
  queued: number;
  sent: number;
  failed: number;
  sentToday: number;
  emailProvider: boolean;
  smsProvider: boolean;
  recent: { id: string; channel: string; recipient: string; subject: string; created_at: string; state: string; attempts: number; sent_at: string | null; last_error: string | null }[];
}

/** What is actually true: the platform's own dashboard, for the offices that operate it. */
export async function PlatformDashboard({ me }: { me: Me | null }) {
  const [status, outbox] = await Promise.all([api<Status>("/api/v1/platform/status"), api<Outbox>("/api/v1/platform/notices")]);
  const db = status.ok ? status.data.database : null;
  const ob = outbox.ok ? outbox.data : null;
  return (
    <>
      <Tiles
        items={[
          ["The service", status.ok ? "up" : "down", status.ok ? "var(--green-ink)" : "var(--red-ink)", status.ok ? `commit ${(status.data.commit ?? "local").slice(0, 12)}` : "not answering"],
          ["The database", db?.reachable ? "reachable" : "unreachable", db?.reachable ? "var(--green-ink)" : "var(--red-ink)", db?.reachable ? `${db.migrationsApplied} migrations · ${db.latestMigration}` : (db?.why ?? "unknown")],
          ["2025/2026 admission settings", db?.admissionSettings2025_2026 ?? "—", null, "Draft until put in force"],
          ["Acting as", me ? officeLabel(me.activeOffice) : "—", null, me ? `${me.offices.length} office${me.offices.length === 1 ? "" : "s"} held` : "no session"],
        ]}
      />
      {!status.ok && <ProblemNotice problem={status.problem} />}
      <Panel title="What is actually true" right={API_URL}>
        <PBody>
          <KvGrid
            cls="grid--3"
            pairs={[
              ["Service", status.ok ? status.data.service : "—"],
              ["Started", status.ok ? new Date(status.data.startedAt).toLocaleString("en-GB") : "—"],
              ["Latest migration", db?.latestMigration ?? "—"],
              ["Actor", me?.actorId ?? "—"],
              ["Acting office", me ? officeLabel(me.activeOffice) : "—"],
              ["Offices held", me ? me.offices.map(officeLabel).join(", ") || "none" : "—"],
            ]}
          />
        </PBody>
      </Panel>
      <Panel title="The outbox" right={ob ? `${ob.queued} waiting · ${ob.sentToday} sent today · ${ob.failed} failed` : "not answering"}>
        <PBody>
          <KvGrid cls="grid--3" pairs={[
            ["Email provider", ob ? (ob.emailProvider ? "wired" : "none — MOAUM_NOTICES_EMAIL_URL is not set") : "—"],
            ["SMS provider", ob ? (ob.smsProvider ? "wired" : "none — MOAUM_NOTICES_SMS_URL is not set") : "—"],
            ["Waiting", ob ? String(ob.queued) : "—"],
            ["Sent", ob ? String(ob.sent) : "—"],
            ["Failed after five attempts", ob ? String(ob.failed) : "—"],
            ["Sent in the last day", ob ? String(ob.sentToday) : "—"],
          ]} />
        </PBody>
        {ob && !ob.emailProvider && !ob.smsProvider ? (
          <div className="card__body"><div className="sub2">Every notice the portal would send is queued here, on the record, and shown to the applicant on their own dashboard. None leaves until a provider is named: an endpoint that takes a POST of to, subject and body with a bearer token, one for email and one for SMS.</div></div>
        ) : null}
        {ob && ob.recent.length ? (
          <DTable cols={["When|mid", "To", "Notice", "Channel|mid", "State|num"]} rows={ob.recent.map((n) => [
            <span className="tnum sub2" key="w">{new Date(n.created_at).toLocaleString("en-GB")}</span>,
            <span className="sub2" key="t">{n.recipient}</span>,
            <span key="s">{n.subject}</span>,
            <span className="sub2" key="c">{n.channel}</span>,
            n.state === "SENT" ? <Pil kind="ok" key="x">Sent</Pil> : n.state === "FAILED" ? <Pil kind="bad" key="x">Failed · {n.last_error ?? ""}</Pil> : <Pil kind="info" key="x">Queued{n.attempts ? ` · ${n.attempts} tried` : ""}</Pil>,
          ])} />
        ) : null}
      </Panel>
      <Note kind="info" title="How attribution works">
        Every request carries a token naming a person and the offices they hold, and the office chosen at the top
        left says which one is acting. The API places that on the transaction; the database records every changed
        row against it, and refuses a change that carries none. There is no unattributed state change &mdash; and
        that is checked, not assumed.
      </Note>
    </>
  );
}
