import { api } from "@/lib/api";
import type { AdmissionCycle } from "@/lib/matriculation";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Admissions } from "./Admissions";

export const dynamic = "force-dynamic";

const SESSION_PATTERN = /^\d{4}\/\d{4}$/;

export default async function AdmissionsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const requested = typeof params.session === "string" ? params.session : "2026/2027";
  const session = SESSION_PATTERN.test(requested) ? requested : "2026/2027";
  const [me, cycle] = await Promise.all([api<Me>("/api/v1/iam/me"), api<AdmissionCycle>(`/api/v1/admissions/sessions/${session}/cycle`)]);
  return (
    <Shell route="t/admissions" me={me.ok ? me.data : null}>
      {cycle.ok ? <Admissions cycle={cycle.data} actingOffice={me.ok ? me.data.activeOffice : null} /> : <ProblemNotice problem={cycle.problem} />}
    </Shell>
  );
}
