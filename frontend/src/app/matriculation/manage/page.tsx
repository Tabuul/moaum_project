import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { IssuedRow, ManagePage, Overview, PendingRow } from "@/lib/matric-manage";
import { Manage, type ManageFilters } from "./Manage";

export const dynamic = "force-dynamic";

const SESSION_PATTERN = /^\d{4}\/\d{4}$/;

/** t/matriculation-manage — the exercise faculty by faculty: eligible students by programme, numbers proposed and reviewed, then issued */
export default async function MatriculationManagePage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const s = (k: string) => (typeof p[k] === "string" ? (p[k] as string).slice(0, 80) : "");
  const requested = s("session") || "2026/2027";
  const session = SESSION_PATTERN.test(requested) ? requested : "2026/2027";
  const filters: ManageFilters = { session, fac: s("fac").toUpperCase(), prog: s("prog").toUpperCase(), status: s("status").toUpperCase(), q: s("q"), tab: s("tab") || "faculty", batch: s("batch") };
  const qs = new URLSearchParams();
  if (filters.fac) qs.set("fac", filters.fac);
  if (filters.prog) qs.set("prog", filters.prog);
  if (filters.status) qs.set("status", filters.status);
  if (filters.q) qs.set("q", filters.q);
  const base = `/api/v1/matriculation/sessions/${session}/management`;
  const iq = new URLSearchParams();
  if (filters.fac) iq.set("fac", filters.fac);
  if (filters.prog) iq.set("prog", filters.prog);
  if (filters.q) iq.set("q", filters.q);
  if (filters.batch) iq.set("batch", filters.batch);
  const [me, page, overview, issued, pending] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<ManagePage>(`${base}?${qs}`),
    api<Overview>(`${base}/overview`),
    api<IssuedRow[]>(`${base}/issued?${iq}`),
    api<PendingRow[]>(`${base}/pending${filters.fac ? `?fac=${encodeURIComponent(filters.fac)}` : ""}`),
  ]);
  return (
    <Shell route="t/matriculation-manage" me={me.ok ? me.data : null}>
      {page.ok ? (
        <Manage page={page.data} overview={overview.ok ? overview.data : null} issued={issued.ok ? issued.data : []} pending={pending.ok ? pending.data : []} filters={filters}
          actingOffice={me.ok ? me.data.activeOffice ?? null : null} />
      ) : <ProblemNotice problem={page.problem} />}
    </Shell>
  );
}
