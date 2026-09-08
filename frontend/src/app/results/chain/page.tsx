import { api } from "@/lib/api";
import { loadScope, scopeParams } from "@/lib/scope-data";
import type { SheetDetail, SheetListing } from "@/lib/results";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Chain } from "./Chain";
import { PickSheet } from "./PickSheet";

export const dynamic = "force-dynamic";

export default async function ChainPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const sheet = typeof params.sheet === "string" && /^[0-9a-f-]{36}$/.test(params.sheet) ? params.sheet : null;
  const me = await api<Me>("/api/v1/iam/me");
  if (!sheet) {
    const { scope, structure, sessions } = await loadScope(params);
    const listing = await api<SheetListing>(`/api/v1/results/sheets?${scopeParams(scope)}`);
    return (
      <Shell route="t/chain" me={me.ok ? me.data : null}>
        {listing.ok ? <PickSheet scope={scope} structure={structure} sessions={sessions} listing={listing.data} /> : <ProblemNotice problem={listing.problem} />}
      </Shell>
    );
  }
  const detail = await api<SheetDetail>(`/api/v1/results/sheets/${sheet}`);
  return (
    <Shell route="t/chain" me={me.ok ? me.data : null}>
      {detail.ok ? <Chain detail={detail.data} actingOffice={me.ok ? me.data.activeOffice : null} /> : <ProblemNotice problem={detail.problem} />}
    </Shell>
  );
}
