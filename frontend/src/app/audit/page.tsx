import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { AuditTrail, type AuditView, type Facets } from "./AuditTrail";

export const dynamic = "force-dynamic";

/** t/audit — the audit trail, read over the hash-chained spine. */
export default async function AuditPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const action = typeof p.action === "string" ? p.action : "";
  const office = typeof p.office === "string" ? p.office : "";
  const q = new URLSearchParams();
  if (action) q.set("action", action);
  if (office) q.set("office", office);
  const [me, view, facets] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<AuditView>(`/api/v1/audit/entries${q.toString() ? `?${q.toString()}` : ""}`),
    api<Facets>("/api/v1/audit/facets"),
  ]);
  return (
    <Shell route="t/audit" me={me.ok ? me.data : null}>
      {view.ok ? <AuditTrail d={view.data} facets={facets.ok ? facets.data : { actions: [], offices: [] }} action={action} office={office} /> : <ProblemNotice problem={view.problem} />}
    </Shell>
  );
}
