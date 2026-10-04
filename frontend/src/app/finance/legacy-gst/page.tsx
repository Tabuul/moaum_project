import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { LegacyGst } from "./LegacyGst";
import type { LegacySummaryPage } from "@/lib/legacy-gst";

export const dynamic = "force-dynamic";

/** t/legacygst — old-portal GST payments reconciled into the GST/EPS entitlement (V323) */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const q = await searchParams;
  const session = typeof q.session === "string" && /^\d{4}\/\d{4}$/.test(q.session) ? q.session : "";
  const tab = typeof q.tab === "string" && ["overview", "upload", "queue", "search", "imports"].includes(q.tab) ? (q.tab as "overview" | "upload" | "queue" | "search" | "imports") : undefined;
  const [me, data] = await Promise.all([api<Me>("/api/v1/iam/me"), api<LegacySummaryPage>(`/api/v1/finance/legacy-gst/summary${session ? `?session=${encodeURIComponent(session)}` : ""}`)]);
  const acting = me.ok ? me.data.activeOffice ?? "" : "";
  return (
    <Shell route="t/legacygst" me={me.ok ? me.data : null} sub={session ? `${session} session` : "every session"}>
      {data.ok ? <LegacyGst data={data.data} canAct={["bursar", "financecontroller", "super"].includes(acting)} initialTab={tab} /> : <ProblemNotice problem={data.problem} />}
    </Shell>
  );
}
