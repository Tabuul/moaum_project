import { api } from "@/lib/api";
import { loadScope, scopeParams } from "@/lib/scope-data";
import type { SheetListing } from "@/lib/results";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Pipeline } from "./Pipeline";

export const dynamic = "force-dynamic";

/** t/pipeline — student to transcript: one journey, and every stage has a name on it */
export default async function PipelinePage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const { scope, structure, sessions } = await loadScope(params);
  const at = typeof params.at === "string" ? Math.max(0, Math.min(8, parseInt(params.at, 10) || 0)) : 0;
  const [me, listing] = await Promise.all([api<Me>("/api/v1/iam/me"), api<SheetListing>(`/api/v1/results/sheets?${scopeParams(scope)}`)]);
  return (
    <Shell route="t/pipeline" me={me.ok ? me.data : null}>
      {listing.ok ? <Pipeline scope={scope} structure={structure} sessions={sessions} listing={listing.data} at={at} /> : <ProblemNotice problem={listing.problem} />}
    </Shell>
  );
}
