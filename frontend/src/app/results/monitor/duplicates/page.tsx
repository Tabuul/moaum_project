import { api } from "@/lib/api";
import { loadScope } from "@/lib/scope-data";
import { Shell, type Me } from "@/components/proto/Shell";
import { Duplicates } from "./Duplicates";

export const dynamic = "force-dynamic";

/** t/resultduplicates — V702: a course's marks on two classes, resolved by the Registry's side */
export default async function DuplicateResultsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const { scope, structure, sessions, ceiling } = await loadScope(params);
  const me = await api<Me>("/api/v1/iam/me");
  return (
    <Shell route="t/resultduplicates" me={me.ok ? me.data : null}>
      <Duplicates scope={scope} structure={structure} sessions={sessions} ceiling={ceiling} />
    </Shell>
  );
}
