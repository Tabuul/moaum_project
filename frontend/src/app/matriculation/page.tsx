import { api } from "@/lib/api";
import type { MatriculationOverview } from "@/lib/matriculation";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { MatriculationScreen } from "./MatriculationScreen";

export const dynamic = "force-dynamic";

const SESSION_PATTERN = /^\d{4}\/\d{4}$/;

export default async function MatriculationPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const requested = typeof params.session === "string" ? params.session : "2026/2027";
  const session = SESSION_PATTERN.test(requested) ? requested : "2026/2027";
  const [me, overview] = await Promise.all([api<Me>("/api/v1/iam/me"), api<MatriculationOverview>(`/api/v1/matriculation/sessions/${session}`)]);
  return (
    <Shell route="t/matriculation" me={me.ok ? me.data : null}>
      {overview.ok ? <MatriculationScreen overview={overview.data} actingOffice={me.ok ? me.data.activeOffice : null} /> : <ProblemNotice problem={overview.problem} />}
    </Shell>
  );
}
