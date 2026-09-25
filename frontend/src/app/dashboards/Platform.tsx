import { api, API_URL } from "@/lib/api";
import { StatsPanel } from "@/components/stats/StatsPanel";
import type { Me } from "@/components/proto/Shell";
import { KvGrid, LinkBtn, Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";
import { ProblemNotice } from "@/components/ProblemNotice";
import { officeLabel } from "@/lib/offices";
import { ResetData } from "./ResetData";

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

interface PersonRow { id: string; username: string | null; liveOffices: number; endedOn: string | null }
interface GrantRow { validTo: string | null }
interface Coverage { total: number; uploaded: number; pending: number; courses: number; byFaculty: { faculty: string; total: number; uploaded: number }[]; pendingList: { code: string; name: string; faculty: string }[] }

/** What is actually true: the platform's own dashboard, for the offices that operate it. */
export async function PlatformDashboard({ me }: { me: Me | null }) {
  const [status, outbox, persons, grants, coverage] = await Promise.all([
    api<Status>("/api/v1/platform/status"),
    api<Outbox>("/api/v1/platform/notices"),
    api<PersonRow[]>("/api/v1/iam/persons"),
    api<GrantRow[]>("/api/v1/iam/office-assignments"),
    api<Coverage>("/api/v1/catalogue/upload-coverage"),
  ]);
  const cov = coverage.ok ? coverage.data : null;
  const db = status.ok ? status.data.database : null;
  const ob = outbox.ok ? outbox.data : null;
  const office = me?.activeOffice ?? null;
  const canManagePeople = ["ict", "admin", "super", "registrar", "dregistrar"].includes(office ?? "");
  const people = persons.ok ? persons.data : [];
  const gr = grants.ok ? grants.data : [];
  // this is an async server component rendered once per request; reading the clock here is correct
  // eslint-disable-next-line react-hooks/purity
  const now = Date.now();
  const withAccount = people.filter((p) => p.username && !p.endedOn).length;
  const soon = gr.filter((g) => g.validTo && new Date(g.validTo).getTime() - now < 30 * 86400000).length;
  return (
    <>
      {cov ? (
        <>
          <StatsPanel />
          <Tiles items={[
            ["Programmes", String(cov.total), null, "on the register"],
            ["Course structure uploaded", String(cov.uploaded), cov.uploaded ? "var(--green-ink)" : null, cov.total ? `${Math.round((100 * cov.uploaded) / cov.total)}% of programmes` : "—"],
            ["Yet to upload", String(cov.pending), cov.pending ? "var(--red-ink)" : "var(--green-ink)", cov.pending ? "no course structure yet" : "every programme covered"],
            ["Courses in the catalogue", cov.courses.toLocaleString(), null, "created and offered"],
          ]} />
          <div className="grid grid--2">
            <Panel title="Upload coverage by faculty" right="programmes with a structure loaded">
              {cov.byFaculty.length ? (
                <DTable cols={["Faculty", "Uploaded|mid", "Pending|mid", "Share|num"]} rows={cov.byFaculty.map((f) => {
                  const pend = Number(f.total) - Number(f.uploaded);
                  const pct = Number(f.total) ? Math.round((100 * Number(f.uploaded)) / Number(f.total)) : 0;
                  return [
                    <span key="f">{f.faculty}</span>,
                    <span className="tnum" key="u">{f.uploaded} of {f.total}</span>,
                    <span className={`tnum${pend ? " ink-red" : ""}`} key="p">{pend}</span>,
                    <span className="tnum sub2" key="s">{pct}%</span>,
                  ];
                })} />
              ) : <PBody><div className="sub2">No programme on the register yet.</div></PBody>}
            </Panel>
            <Panel title="Programmes yet to upload" right={cov.pending ? `${cov.pending} pending` : "none"}>
              {cov.pendingList.length ? (
                <DTable cols={["Programme", "Faculty"]} texts={cov.pendingList.map((p) => `${p.code} ${p.name} ${p.faculty}`)}
                  rows={cov.pendingList.map((p) => [
                    <span key="p"><b className="tnum">{p.code}</b> · {p.name}</span>,
                    <span className="sub2" key="f">{p.faculty}</span>,
                  ])} />
              ) : <PBody><div className="sub2">Every programme on the register has its course structure loaded.</div></PBody>}
            </Panel>
          </div>
          <Note kind="info" title="Course-structure upload">
            A programme counts as uploaded once its CCMAS structure has been loaded and its courses offered to it. Load a structure on <a href="/catalogue/upload">Course structure upload</a>; browse a department&rsquo;s courses on <a href="/catalogue">Dept courses</a>.
          </Note>
        </>
      ) : null}
      {canManagePeople ? (
        <Panel title="People and access" right={persons.ok ? `${people.length} people · ${withAccount} with an account` : "not answering"}>
          <PBody>
            <Note kind="info" title="Create a person, give them an account, grant the office they hold">
              A person is created once, however many offices they come to hold. Creating the account sets a first password the holder must change. Granting an office is bounded, dated and carries the authority that made it &mdash; every act here is recorded against your name.
            </Note>
            <div className="row mt-1">
              <LinkBtn kind="primary" href="/people?new=person">+ New person</LinkBtn>
              <LinkBtn kind="primary" href="/people?new=grant">+ Grant an office</LinkBtn>
              <LinkBtn kind="ghost" href="/people">Open the people console</LinkBtn>
            </div>
          </PBody>
          <KvGrid cls="grid--4" pairs={[
            ["People on record", persons.ok ? String(people.length) : "—"],
            ["With a sign-in account", persons.ok ? String(withAccount) : "—"],
            ["Offices held (live grants)", grants.ok ? String(gr.length) : "—"],
            ["Grants ending within 30 days", grants.ok ? String(soon) : "—"],
          ]} />
        </Panel>
      ) : null}
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
          <PBody><div className="sub2">Every notice the portal would send is queued here, on the record, and shown to the applicant on their own dashboard. None leaves until a provider is named: an endpoint that takes a POST of to, subject and body with a bearer token, one for email and one for SMS.</div></PBody>
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
      <ResetData office={office} />
      <Note kind="info" title="How attribution works">
        Every request carries a token naming a person and the offices they hold, and the office chosen at the top
        left says which one is acting. The API places that on the transaction; the database records every changed
        row against it, and refuses a change that carries none. There is no unattributed state change &mdash; and
        that is checked, not assumed.
      </Note>
    </>
  );
}
