import { api } from "@/lib/api";
import { loadScope } from "@/lib/scope-data";
import { Shell, type Me } from "@/components/proto/Shell";
import { ResultViewer } from "./ResultViewer";

export const dynamic = "force-dynamic";

/** t/resultviewer — V700: the Director of ICT's result viewer, by faculty, department, programme, level, session and semester */
export default async function ResultViewerPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const { scope, structure, sessions, ceiling } = await loadScope(params);
  const me = await api<Me>("/api/v1/iam/me");
  const state = typeof params.state === "string" ? params.state : undefined;
  return (
    <Shell route="t/resultviewer" me={me.ok ? me.data : null}>
      <ResultViewer scope={scope} structure={structure} sessions={sessions} ceiling={ceiling} initialState={state} />
    </Shell>
  );
}
