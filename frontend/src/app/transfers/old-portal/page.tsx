import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { LEGACY_STATUSES, legacyRow, snakeKeys } from "@/lib/transfer-fees";
import { OldPortalTransfers, type LegacyLoad, type LegacyReport, type LegacyScope } from "./OldPortalTransfers";

export const dynamic = "force-dynamic";

const BASE = "/api/v1/transfers/legacy";

/** t/oldtransfers — V727: the old portal's inter-departmental transfer payments of the current exercise, each counted toward the
 *  student's application, awaiting one, or unmatched with the reason, and an officer's decision on any of them; the scope (from which
 *  date, which items); the old portal's applications brought in from its export (checked, then loaded); the loads; and the
 *  reconciliation report, read from the records as they stand */
export default async function OldPortalTransfersPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const status = typeof p.status === "string" && (LEGACY_STATUSES as readonly string[]).includes(p.status) ? p.status : "";
  const search = typeof p.search === "string" ? p.search.trim().slice(0, 80) : "";
  const tab = typeof p.tab === "string" ? p.tab : "";
  const q = new URLSearchParams();
  if (status) q.set("status", status);
  if (search) q.set("search", search);
  const [me, list, scope, loads, report] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<{ rows?: Record<string, unknown>[]; counts?: Record<string, number>; total?: number }>(`${BASE}${q.toString() ? `?${q.toString()}` : ""}`),
    api<LegacyScope>(`${BASE}/scope`),
    api<Record<string, unknown>[]>(`${BASE}/loads`),
    api<LegacyReport>(`${BASE}/report`),
  ]);
  return (
    <Shell route="t/oldtransfers" me={me.ok ? me.data : null}>
      {list.ok ? (
        <OldPortalTransfers
          rows={(list.data.rows ?? []).map(legacyRow)}
          counts={list.data.counts ?? {}}
          matching={list.data.total ?? (list.data.rows ?? []).length}
          status={status}
          search={search}
          initialTab={tab}
          scope={scope.ok ? scope.data : null}
          scopeProblem={scope.ok ? null : scope.problem}
          loads={loads.ok ? (Array.isArray(loads.data) ? loads.data : []).map((r) => snakeKeys<LegacyLoad>(r)) : null}
          loadsProblem={loads.ok ? null : loads.problem}
          report={report.ok ? report.data : null}
          reportProblem={report.ok ? null : report.problem}
          actingOffice={me.ok ? me.data.activeOffice : null}
        />
      ) : <ProblemNotice problem={list.problem} />}
    </Shell>
  );
}
