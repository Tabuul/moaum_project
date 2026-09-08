import { api } from "@/lib/api";
import { KINDS, type SearchResult } from "@/lib/student";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Search } from "./Search";

export const dynamic = "force-dynamic";

export default async function SearchPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const params = await searchParams;
  const q = typeof params.q === "string" ? params.q.trim() : "";
  const asked = typeof params.kind === "string" ? params.kind : "all";
  const kind = KINDS.some((k) => k[0] === asked) ? asked : "all";

  const [me, result] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    q
      ? api<SearchResult>(`/api/v1/student/search?q=${encodeURIComponent(q)}&kind=${kind}`)
      : Promise.resolve(null),
  ]);

  return (
    <Shell route="t/search" me={me.ok ? me.data : null}>
      {result && !result.ok ? (
        <ProblemNotice problem={result.problem} />
      ) : (
        <Search q={q} kind={kind} result={result && result.ok ? result.data : null} />
      )}
    </Shell>
  );
}
