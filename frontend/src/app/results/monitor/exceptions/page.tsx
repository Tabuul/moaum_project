import { api } from "@/lib/api";
import { loadScope } from "@/lib/scope-data";
import { Shell, type Me } from "@/components/proto/Shell";
import { Exceptions } from "./Exceptions";

export const dynamic = "force-dynamic";

/** t/resultexceptions — V700: the results that need a look */
export default async function ResultExceptionsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const { scope, structure, sessions, ceiling } = await loadScope(params);
  const me = await api<Me>("/api/v1/iam/me");
  return (
    <Shell route="t/resultexceptions" me={me.ok ? me.data : null}>
      <Exceptions scope={scope} structure={structure} sessions={sessions} ceiling={ceiling} initialKind={typeof params.kind === "string" ? params.kind : undefined} />
    </Shell>
  );
}
