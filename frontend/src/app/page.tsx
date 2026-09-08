import { api, API_URL } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { KvGrid, Note, Panel, PBody, Tiles } from "@/components/proto/ui";
import { ProblemNotice } from "@/components/ProblemNotice";
import { officeLabel } from "@/lib/offices";

export const dynamic = "force-dynamic";

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

export default async function DashboardPage() {
  const [status, me] = await Promise.all([api<Status>("/api/v1/platform/status"), api<Me>("/api/v1/iam/me")]);
  const db = status.ok ? status.data.database : null;

  return (
    <Shell route="r/academic" me={me.ok ? me.data : null}>
      <Tiles
        items={[
          ["The service", status.ok ? "up" : "down", status.ok ? "var(--green-ink)" : "var(--red-ink)", status.ok ? `commit ${(status.data.commit ?? "local").slice(0, 12)}` : "not answering"],
          ["The database", db?.reachable ? "reachable" : "unreachable", db?.reachable ? "var(--green-ink)" : "var(--red-ink)", db?.reachable ? `${db.migrationsApplied} migrations · ${db.latestMigration}` : (db?.why ?? "unknown")],
          ["2025/2026 admission settings", db?.admissionSettings2025_2026 ?? "—", null, "Draft until put in force"],
          ["Acting as", me.ok ? officeLabel(me.data.activeOffice) : "—", null, me.ok ? `${me.data.offices.length} office${me.data.offices.length === 1 ? "" : "s"} held` : "no token"],
        ]}
      />

      {!status.ok && <ProblemNotice problem={status.problem} />}
      {!me.ok && <ProblemNotice problem={me.problem} />}

      <Panel title="What is actually true" right={API_URL}>
        <PBody>
          <KvGrid
            cls="grid--3"
            pairs={[
              ["Service", status.ok ? status.data.service : "—"],
              ["Started", status.ok ? new Date(status.data.startedAt).toLocaleString("en-GB") : "—"],
              ["Latest migration", db?.latestMigration ?? "—"],
              ["Actor", me.ok ? me.data.actorId : "—"],
              ["Acting office", me.ok ? officeLabel(me.data.activeOffice) : "—"],
              ["Offices held", me.ok ? me.data.offices.map(officeLabel).join(", ") || "none" : "—"],
            ]}
          />
        </PBody>
      </Panel>

      <Note kind="info" title="How attribution works">
        Every request carries a token naming a person and the offices they hold, and the office chosen at the top
        left says which one is acting. The API places that on the transaction; the database records every changed
        row against it, and refuses a change that carries none. There is no unattributed state change &mdash; and
        that is checked, not assumed.
      </Note>
    </Shell>
  );
}
