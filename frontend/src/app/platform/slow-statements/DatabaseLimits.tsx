/**
 * 11 November 2026: the time limits the live database places on the portal's statements, where each was set, the portal's own
 * limits, and the statements the database stopped since the API started — what ICT reads when a screen says it was stopped.
 */
import { Note, Panel, PBody } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

export interface LimitSetting { name: string; setting: string; unit: string | null; source: string; reset_val: string; boot_val: string }
export interface StoppedStatement {
  at: string; cause: string; transaction: string | null; portalLimitMs: number | null; ranForMs: number | null;
  method: string; route: string; office: string | null; reference: string; databaseSaid: string | null;
}
export interface DatabaseLimitsData {
  settings: LimitSetting[];
  database: { name: string; role: string; version: string; superuser: boolean };
  defaults: { scope: string; name: string; value: string }[] | null;
  defaultsUnreadable?: string;
  portal: {
    readLimitMs: number | null; transactionTimeoutSeconds: number | null; queryTimeoutSeconds: number | null; connectionOptions: string | null; poolSize: number | null;
    paydirectDoorLimitMs?: number | null; paydirectDoorLockLimitMs?: number | null;
  };
  reading: string;
  stopped: StoppedStatement[];
  stoppedTotal: number;
  since: string;
}

const NAMES: Record<string, string> = {
  statement_timeout: "One statement",
  lock_timeout: "Waiting for a lock",
  idle_in_transaction_session_timeout: "Idle inside a transaction",
  transaction_timeout: "One transaction",
  idle_session_timeout: "An idle connection",
};
const SOURCES: Record<string, string> = {
  default: "PostgreSQL's default",
  "configuration file": "The server's configuration",
  database: "The database",
  user: "The portal's database role",
  "database user": "The role in this database",
  client: "The connection's options",
  session: "Set on the connection",
  global: "Every role (ALTER ROLE ALL)",
};
const CAUSES: Record<string, string> = {
  PORTAL_READ_LIMIT: "The portal's read limit",
  PAYDIRECT_DOOR_LIMIT: "The PAYDirect door's limit",
  DATABASE_STATEMENT_TIMEOUT: "The database's statement timeout",
  CANCEL_REQUEST: "A cancel request",
  OTHER: "Other",
};

/** a setting as a person reads it: 0 is no limit; 90000 ms is 90 s */
function limitWords(value: string, unit: string | null): string {
  const n = Number(value);
  if (!Number.isFinite(n)) return value;
  if (n === 0) return "No limit";
  const ms = unit === "s" ? n * 1000 : unit === "min" ? n * 60000 : unit === "h" ? n * 3600000 : n;
  return secs(ms);
}
function secs(ms: number): string {
  if (ms >= 120000) {
    const s = Math.round(ms / 1000);
    return `${Math.floor(s / 60)} min${s % 60 ? ` ${s % 60} s` : ""}`;
  }
  return ms >= 10000 || ms % 1000 === 0 ? `${Math.round(ms / 1000)} s` : `${(ms / 1000).toFixed(1)} s`;
}
const when = (iso: string) => new Date(iso).toLocaleString("en-GB", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit", second: "2-digit", timeZone: "Africa/Lagos" });

export function DatabaseLimits({ d }: { d: DatabaseLimitsData }) {
  const statement = d.settings.find((s) => s.name === "statement_timeout");
  const transaction = d.settings.find((s) => s.name === "transaction_timeout");
  const databaseLimit = (statement && Number(statement.setting) > 0) || (transaction && Number(transaction.setting) > 0);
  const writeLimited = d.portal.queryTimeoutSeconds != null || d.portal.transactionTimeoutSeconds != null;
  return (
    <Panel title="Time limits and stopped statements" right={`${d.database.name} · PostgreSQL ${d.database.version}`}>
      <PBody>
        <Note kind={databaseLimit ? "bad" : "info"} title={databaseLimit ? "The database stops the portal's work after a time" : "The database sets no statement time limit"}>
          {d.reading}
        </Note>
        <DTable
          cols={["Limit", "Now", "Set by", "Returns to", "PostgreSQL's default"]}
          rows={d.settings.map((s) => [
            NAMES[s.name] ?? s.name,
            limitWords(s.setting, s.unit),
            SOURCES[s.source] ?? s.source,
            limitWords(s.reset_val, s.unit),
            limitWords(s.boot_val, s.unit),
          ])}
          texts={d.settings.map((s) => `${s.name} ${s.source}`)}
        />
        {d.defaults && d.defaults.length ? (
          <DTable cols={["Stated on", "Limit", "Value"]}
            rows={d.defaults.map((x) => [x.scope === "all roles" ? "Every role" : x.scope === "role" ? `The role ${d.database.role}` : x.scope === "database" ? `The database ${d.database.name}` : `The role ${d.database.role} in ${d.database.name}`, NAMES[x.name] ?? x.name, x.value])}
            texts={d.defaults.map((x) => `${x.scope} ${x.name} ${x.value}`)} />
        ) : d.defaultsUnreadable ? <Note kind="info" title="The stated defaults could not be read">{d.defaultsUnreadable}</Note> : null}
        <p className="sub2 mt-1">
          The portal&rsquo;s own limits: a screen&rsquo;s read {d.portal.readLimitMs ? secs(d.portal.readLimitMs) : "unlimited"}
          {writeLimited ? "" : "; a write unlimited"}
          {d.portal.transactionTimeoutSeconds ? `; every transaction, read or write, ${d.portal.transactionTimeoutSeconds} s` : ""}
          {d.portal.queryTimeoutSeconds ? `; every statement, read or write, ${d.portal.queryTimeoutSeconds} s` : ""}
          {d.portal.paydirectDoorLimitMs ? `; the PAYDirect door's statements ${secs(d.portal.paydirectDoorLimitMs)}` : ""}
          {d.portal.connectionOptions ? `; the connection's options: ${d.portal.connectionOptions}` : ""}.
          Read as the role {d.database.role}{d.database.superuser ? " (a superuser)" : ""}.
        </p>
      </PBody>
      {d.stopped.length === 0 ? (
        <PBody><Note kind="ok" title="Nothing stopped">No statement has been stopped on a request this API instance answered since it started ({when(d.since)}). Each instance keeps its own list and a redeploy empties it; a scheduled job&rsquo;s stopped statements are in the server&rsquo;s logs. Only statement time limits and cancels are listed: a lock wait or a transaction cut by the database is answered otherwise.</Note></PBody>
      ) : <DTable
        cols={["When", "Screen", "Transaction", "What stopped it", "Ran for", "Office", "Reference"]}
        rows={d.stopped.map((s) => [
          when(s.at),
          <span key="r" className="mono">{s.method} {s.route}</span>,
          s.transaction === "READ" ? "Read" : s.transaction === "WRITE" ? "Write" : "—",
          <span key="w">{`${CAUSES[s.cause] ?? s.cause}${s.portalLimitMs ? ` (${secs(s.portalLimitMs)})` : ""}`}{s.databaseSaid ? <span className="sub2" style={{ display: "block" }}>&ldquo;{s.databaseSaid}&rdquo;</span> : null}</span>,
          s.ranForMs == null ? "—" : secs(s.ranForMs),
          s.office ?? "—",
          <span key="c" className="mono sub2">{s.reference.slice(0, 8)}</span>,
        ])}
        texts={d.stopped.map((s) => `${s.route} ${s.cause} ${s.office ?? ""} ${s.reference} ${s.databaseSaid ?? ""}`)}
      />}
      {d.stoppedTotal > d.stopped.length ? <PBody><p className="sub2">{d.stoppedTotal.toLocaleString()} stopped on this API instance since it started; the latest {d.stopped.length} are listed.</p></PBody> : null}
    </Panel>
  );
}
