import { api } from "@/lib/api";
import { loadScope, scopeParams } from "@/lib/scope-data";
import type { ClearanceListing, ClearancePosition } from "@/lib/credentials";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { ClearanceScreen } from "./ClearanceScreen";

export const dynamic = "force-dynamic";

export default async function ClearancePage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const { scope, structure, sessions } = await loadScope(params);
  const purpose = typeof params.purpose === "string" && /^[A-Z_]+$/.test(params.purpose) ? params.purpose : "CONVOCATION";
  const student = typeof params.student === "string" && /^[0-9a-f-]{36}$/.test(params.student) ? params.student : null;
  const [me, listing] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<ClearanceListing>(`/api/v1/clearance?${scopeParams(scope, { purpose })}`),
  ]);
  const chosen = student ?? (listing.ok ? listing.data.candidates.find((c) => !c.cleared)?.id ?? null : null);
  const position = chosen ? await api<ClearancePosition[]>(`/api/v1/clearance/students/${chosen}?purpose=${purpose}`) : null;
  return (
    <Shell route="t/clearance" me={me.ok ? me.data : null}>
      {listing.ok ? (
        <ClearanceScreen scope={scope} structure={structure} sessions={sessions} listing={listing.data} chosen={chosen} position={position && position.ok ? position.data : []} actingOffice={me.ok ? me.data.activeOffice : null} />
      ) : (
        <ProblemNotice problem={listing.problem} />
      )}
    </Shell>
  );
}
