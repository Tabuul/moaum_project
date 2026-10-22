import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { AuditTrail, type AuditScope, type AuditView, type Facets } from "./AuditTrail";

export const dynamic = "force-dynamic";

/** t/audit — the audit trail, read over the hash-chained spine. */
export default async function AuditPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const one = (k: string) => (typeof p[k] === "string" ? (p[k] as string) : "");
  // V627: a date range (yyyy-mm-dd, in Lagos) and a "who" besides the domain and the office
  const isDay = (v: string) => (/^\d{4}-\d{2}-\d{2}$/.test(v) ? v : "");
  const scope: AuditScope = { action: one("action"), office: one("office"), from: isDay(one("from")), to: isDay(one("to")), who: one("who").trim() };
  const q = new URLSearchParams();
  for (const [k, v] of Object.entries(scope)) if (v) q.set(k, v);
  const fq = new URLSearchParams();
  for (const k of ["from", "to", "who"] as const) if (scope[k]) fq.set(k, scope[k]);
  const [me, view, facets] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<AuditView>(`/api/v1/audit/entries${q.toString() ? `?${q.toString()}` : ""}`),
    api<Facets>(`/api/v1/audit/facets${fq.toString() ? `?${fq.toString()}` : ""}`),
  ]);
  return (
    <Shell route="t/audit" me={me.ok ? me.data : null}>
      {view.ok ? <AuditTrail key={scope.who} d={view.data} facets={facets.ok ? facets.data : { actions: [], offices: [] }} scope={scope} /> : <ProblemNotice problem={view.problem} />}
    </Shell>
  );
}
