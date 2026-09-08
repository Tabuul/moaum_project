import { api } from "@/lib/api";
import { loadScope, scopeParams } from "@/lib/scope-data";
import type { SheetListing } from "@/lib/results";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Desk } from "./Desk";

export const dynamic = "force-dynamic";

/** t/resultdesk — the stage this office holds: what is on the desk, what has not arrived, what was sent on */
export default async function DeskPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const { scope, structure, sessions } = await loadScope(params);
  const [me, listing] = await Promise.all([api<Me>("/api/v1/iam/me"), api<SheetListing>(`/api/v1/results/sheets?${scopeParams(scope)}`)]);
  return (
    <Shell route="t/resultdesk" me={me.ok ? me.data : null}>
      {listing.ok ? <Desk scope={scope} structure={structure} sessions={sessions} listing={listing.data} actingOffice={me.ok ? me.data.activeOffice : null} /> : <ProblemNotice problem={listing.problem} />}
    </Shell>
  );
}
