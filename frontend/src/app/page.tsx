import { api, API_URL } from "@/lib/api";
import { ProblemNotice } from "@/components/ProblemNotice";

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

interface Me {
  actorId: string;
  activeOffice: string | null;
  offices: string[];
  correlationId: string | null;
}

export default async function StatusPage() {
  const [status, me] = await Promise.all([api<Status>("/api/v1/platform/status"), api<Me>("/api/v1/iam/me")]);

  return (
    <div className="space-y-8">
      <div>
        <p className="text-xs font-semibold uppercase tracking-wide text-faint">Directorate of ICT</p>
        <h1 className="font-serif text-3xl font-bold text-chrome">What is actually true</h1>
        <p className="mt-1 max-w-2xl text-muted">
          The same questions the prototype&apos;s <span className="font-mono text-xs">/healthz</span> answers, asked
          of the Spring Boot service at <span className="font-mono text-xs">{API_URL}</span>.
        </p>
      </div>

      <section className="grid gap-4 md:grid-cols-2">
        <Card title="The service">
          {status.ok ? (
            <Rows
              rows={[
                ["Service", status.data.service],
                ["Commit", status.data.commit ?? "not stamped (local build)"],
                ["Started", new Date(status.data.startedAt).toLocaleString("en-GB")],
              ]}
            />
          ) : (
            <ProblemNotice problem={status.problem} />
          )}
        </Card>

        <Card title="The database">
          {status.ok ? (
            status.data.database.reachable ? (
              <Rows
                rows={[
                  ["Reachable", "yes"],
                  ["Migrations applied", String(status.data.database.migrationsApplied ?? "—")],
                  ["Latest", status.data.database.latestMigration ?? "—"],
                  ["2025/2026 admission settings", status.data.database.admissionSettings2025_2026 ?? "absent"],
                ]}
              />
            ) : (
              <p className="text-red-ink">
                Not reachable — <span className="text-ink">{status.data.database.why}</span>
              </p>
            )
          ) : (
            <p className="text-faint">Unknown until the service answers.</p>
          )}
        </Card>

        <Card title="Who this frontend acts as">
          {me.ok ? (
            <Rows
              rows={[
                ["Actor", me.data.actorId],
                ["Acting office", me.data.activeOffice ?? "none — reads only"],
                ["Offices held", me.data.offices.join(", ") || "none"],
              ]}
            />
          ) : (
            <ProblemNotice problem={me.problem} />
          )}
        </Card>

        <Card title="How attribution works">
          <p className="text-muted">
            Every request carries a token naming a person and the offices they hold, and{" "}
            <span className="font-mono text-xs">X-Active-Office</span> says which one is acting. The API places that on
            the transaction; the database records every changed row against it, and refuses a change that carries
            none. There is no unattributed state change — and that is checked, not assumed.
          </p>
        </Card>
      </section>
    </div>
  );
}

function Card({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="rounded-lg border border-line bg-surface p-5">
      <h2 className="mb-3 font-serif text-base font-bold text-chrome">{title}</h2>
      {children}
    </section>
  );
}

function Rows({ rows }: { rows: [string, string][] }) {
  return (
    <dl className="grid grid-cols-[max-content_1fr] gap-x-6 gap-y-1.5 text-sm">
      {rows.map(([k, v]) => (
        <div key={k} className="contents">
          <dt className="text-faint">{k}</dt>
          <dd className="tnum break-all text-ink">{v}</dd>
        </div>
      ))}
    </dl>
  );
}
