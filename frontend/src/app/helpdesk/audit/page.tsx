import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { SupportAudit, type AuditList, type AuditFilters } from "./SupportAudit";

export const dynamic = "force-dynamic";

/** t/supportaudit — the support desk's own audit (V346): every support act across the students within the reader's reach. */
export default async function SupportAuditPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const s = (k: string) => (typeof p[k] === "string" ? (p[k] as string) : "");
  const filters: AuditFilters = { module: s("module"), action: s("action"), from: s("from"), to: s("to"), overrides: s("overrides") === "true" ? "true" : "" };
  const page = Math.max(1, Number(s("page") || "1") || 1);
  const qs = new URLSearchParams();
  for (const [k, v] of Object.entries(filters)) if (v) qs.set(k, v);
  qs.set("page", String(page));
  const [me, list] = await Promise.all([api<Me>("/api/v1/iam/me"), api<AuditList>(`/api/v1/helpdesk/support/actions?${qs.toString()}`)]);
  return (
    <Shell route="t/supportaudit" me={me.ok ? me.data : null}>
      {!list.ok ? <ProblemNotice problem={list.problem} /> : <SupportAudit list={list.data} filters={filters} page={page} generatedBy={me.ok ? me.data.name ?? null : null} />}
    </Shell>
  );
}
