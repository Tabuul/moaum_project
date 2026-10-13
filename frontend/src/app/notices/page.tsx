import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Notices, type Filters, type Outbox } from "./Notices";

export const dynamic = "force-dynamic";

/** t/notify and t/channels — the outbox: what waits, what went, and whether a provider is wired; V425: the history searched. */
export default async function NoticesPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const q = await searchParams;
  const one = (k: string) => { const v = q[k]; return (Array.isArray(v) ? v[0] : v) ?? ""; };
  const filters: Filters = { channel: one("channel"), state: one("state"), kind: one("kind"), q: one("q"), from: one("from"), to: one("to") };
  const p = new URLSearchParams();
  (Object.keys(filters) as (keyof Filters)[]).forEach((k) => { if (filters[k]) p.set(k, filters[k]); });
  const [me, outbox] = await Promise.all([api<Me>("/api/v1/iam/me"), api<Outbox>(`/api/v1/platform/notices${p.toString() ? `?${p}` : ""}`)]);
  return (
    <Shell route={me.ok && me.data.activeOffice === "super" ? "t/channels" : "t/notify"} me={me.ok ? me.data : null}>
      {outbox.ok ? <Notices d={outbox.data} actingOffice={me.ok ? me.data.activeOffice : null} filters={filters} /> : <ProblemNotice problem={outbox.problem} />}
    </Shell>
  );
}
