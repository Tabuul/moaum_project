import { api } from "@/lib/api";
import { loadScope } from "@/lib/scope-data";
import { Shell, type Me } from "@/components/proto/Shell";
import { Corrections } from "./Corrections";

export const dynamic = "force-dynamic";

/** t/resultcorrections — V700: the correction requests and the amendments */
export default async function ResultCorrectionsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const { scope, structure, sessions, ceiling } = await loadScope(params);
  const me = await api<Me>("/api/v1/iam/me");
  return (
    <Shell route="t/resultcorrections" me={me.ok ? me.data : null}>
      <Corrections scope={scope} structure={structure} sessions={sessions} ceiling={ceiling} initialState={typeof params.state === "string" ? params.state : undefined} />
    </Shell>
  );
}
