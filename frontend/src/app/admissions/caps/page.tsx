import { api } from "@/lib/api";
import { ProblemNotice } from "@/components/ProblemNotice";

export const dynamic = "force-dynamic";

interface CapsBatch {
  id: string;
  session: string;
  source: string;
  filename: string | null;
  fileSha256: string;
  rowsRead: number;
  listKind: "UTME" | "DIRECT_ENTRY";
  downloadedOn: string;
  uploadedAt: string;
  uploadedBy: string;
  uploadedOffice: string;
  committedAt: string | null;
}

interface Finding {
  finding: string;
  n: number;
  owner: string;
  whatItMeans: string;
}

interface PolicyFinding {
  finding: string;
  detail: string;
  owner: string;
}

const SESSION_PATTERN = /^\d{4}\/\d{4}$/;

export default async function CapsIntakePage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const params = await searchParams;
  const requested = typeof params.session === "string" ? params.session : "2026/2027";
  const session = SESSION_PATTERN.test(requested) ? requested : "2026/2027";

  const [batches, reconciliation, attachments, policy] = await Promise.all([
    api<CapsBatch[]>(`/api/v1/admissions/caps-batches?session=${encodeURIComponent(session)}`),
    api<Finding[]>(`/api/v1/admissions/sessions/${session}/reconciliation`),
    api<Finding[]>(`/api/v1/admissions/sessions/${session}/attachments`),
    api<PolicyFinding[]>(`/api/v1/admissions/sessions/${session}/policy-findings`),
  ]);

  return (
    <div className="space-y-8">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <p className="text-xs font-semibold uppercase tracking-wide text-faint">Academic Office · Admissions</p>
          <h1 className="font-serif text-3xl font-bold text-chrome">The admission list, {session}</h1>
          <p className="mt-1 max-w-2xl text-muted">
            The CAPS list as JAMB sent it, kept whole. Nothing is built on it until every finding below reads zero.
          </p>
        </div>
        <form className="flex items-center gap-2 text-sm" method="get">
          <label htmlFor="session" className="text-faint">
            Session
          </label>
          <input
            id="session"
            name="session"
            defaultValue={session}
            pattern="\d{4}/\d{4}"
            className="tnum w-28 rounded border border-line bg-surface px-2 py-1"
          />
          <button type="submit" className="rounded bg-chrome px-3 py-1 text-white hover:bg-chrome-2">
            Show
          </button>
        </form>
      </div>

      <section>
        <h2 className="mb-2 font-serif text-lg font-bold text-chrome">Lists loaded</h2>
        {batches.ok ? (
          batches.data.length === 0 ? (
            <p className="rounded border border-sky-line bg-sky-bg px-4 py-3 text-sm text-ink">
              No admission list has been loaded for {session} yet. The list is loaded by the Academic Office or the
              Registrar, with its kind — UTME or Direct Entry — declared before the file is read.
            </p>
          ) : (
            <div className="overflow-x-auto rounded-lg border border-line bg-surface">
              <table className="w-full text-sm">
                <thead className="bg-page text-left text-xs uppercase tracking-wide text-faint">
                  <tr>
                    <th className="px-4 py-2">Kind</th>
                    <th className="px-4 py-2">File</th>
                    <th className="px-4 py-2 text-right">Rows</th>
                    <th className="px-4 py-2">Downloaded</th>
                    <th className="px-4 py-2">Loaded</th>
                    <th className="px-4 py-2">By</th>
                    <th className="px-4 py-2">State</th>
                  </tr>
                </thead>
                <tbody>
                  {batches.data.map((b) => (
                    <tr key={b.id} className="border-t border-line-2">
                      <td className="px-4 py-2 font-semibold">{b.listKind === "UTME" ? "UTME" : "Direct Entry"}</td>
                      <td className="px-4 py-2">
                        {b.filename ?? <span className="text-faint">{b.source}</span>}
                        <span className="ml-2 font-mono text-[11px] text-faint">{b.fileSha256.slice(0, 12)}…</span>
                      </td>
                      <td className="tnum px-4 py-2 text-right">{b.rowsRead}</td>
                      <td className="tnum px-4 py-2">{b.downloadedOn}</td>
                      <td className="tnum px-4 py-2">{new Date(b.uploadedAt).toLocaleString("en-GB")}</td>
                      <td className="px-4 py-2">{b.uploadedOffice}</td>
                      <td className="px-4 py-2">
                        {b.committedAt ? (
                          <span className="rounded bg-green-bg px-2 py-0.5 text-green-ink">committed</span>
                        ) : (
                          <span className="rounded bg-sky-bg px-2 py-0.5 text-chrome">held</span>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )
        ) : (
          <ProblemNotice problem={batches.problem} />
        )}
      </section>

      <div className="grid gap-6 lg:grid-cols-2">
        <FindingsSection title="Does the list reconcile?" result={reconciliation} />
        <FindingsSection title="Attachments around the list" result={attachments} />
      </div>

      <section>
        <h2 className="mb-2 font-serif text-lg font-bold text-chrome">The session&apos;s admission policy</h2>
        {policy.ok ? (
          policy.data.length === 0 ? (
            <p className="rounded border border-green-line bg-green-bg px-4 py-3 text-sm text-green-ink">
              Nothing stands between this session&apos;s policy and being in force.
            </p>
          ) : (
            <ul className="divide-y divide-line-2 rounded-lg border border-line bg-surface">
              {policy.data.map((f, i) => (
                <li key={i} className="px-4 py-3 text-sm">
                  <p className="font-semibold text-ink">{f.finding}</p>
                  <p className="text-muted">{f.detail}</p>
                  <p className="text-xs text-faint">{f.owner}</p>
                </li>
              ))}
            </ul>
          )
        ) : (
          <ProblemNotice problem={policy.problem} />
        )}
      </section>
    </div>
  );
}

function FindingsSection({
  title,
  result,
}: {
  title: string;
  result: Awaited<ReturnType<typeof api<Finding[]>>>;
}) {
  return (
    <section>
      <h2 className="mb-2 font-serif text-lg font-bold text-chrome">{title}</h2>
      {result.ok ? (
        <ul className="divide-y divide-line-2 rounded-lg border border-line bg-surface">
          {result.data.map((f, i) => (
            <li key={i} className="flex gap-4 px-4 py-3 text-sm">
              <span
                className={`tnum w-12 shrink-0 text-right font-serif text-lg font-bold ${
                  f.n > 0 ? "text-red-ink" : "text-green-ink"
                }`}
              >
                {f.n}
              </span>
              <span>
                <span className="block font-semibold text-ink">{f.finding}</span>
                <span className="block text-muted">{f.whatItMeans}</span>
                <span className="block text-xs text-faint">{f.owner}</span>
              </span>
            </li>
          ))}
          {result.data.length === 0 && <li className="px-4 py-3 text-sm text-faint">Nothing to report.</li>}
        </ul>
      ) : (
        <ProblemNotice problem={result.problem} />
      )}
    </section>
  );
}
