import { api } from "@/lib/api";
import type { AttachmentState } from "@/lib/matriculation";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { CandidateData } from "./CandidateData";

export const dynamic = "force-dynamic";

const SESSION_PATTERN = /^\d{4}\/\d{4}$/;

export default async function CandidateDataPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const requested = typeof params.session === "string" ? params.session : "2026/2027";
  const session = SESSION_PATTERN.test(requested) ? requested : "2026/2027";
  const [me, state] = await Promise.all([api<Me>("/api/v1/iam/me"), api<AttachmentState>(`/api/v1/admissions/sessions/${session}/candidate-data`)]);
  return (
    <Shell route="t/candidatedata" me={me.ok ? me.data : null}>
      {state.ok ? <CandidateData state={state.data} actingOffice={me.ok ? me.data.activeOffice : null} /> : <ProblemNotice problem={state.problem} />}
    </Shell>
  );
}
