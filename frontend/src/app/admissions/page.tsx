import { api } from "@/lib/api";
import type { AdmissionCycle } from "@/lib/matriculation";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Admissions } from "./Admissions";
import { ApplicantsDesk, type Desk } from "./ApplicantsDesk";
import { Reconsiderations } from "./Reconsiderations";

export const dynamic = "force-dynamic";

const SESSION_PATTERN = /^\d{4}\/\d{4}$/;

export default async function AdmissionsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const requested = typeof params.session === "string" ? params.session : "2026/2027";
  const session = SESSION_PATTERN.test(requested) ? requested : "2026/2027";
  const [me, cycle, desk] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<AdmissionCycle>(`/api/v1/admissions/sessions/${session}/cycle`),
    api<Desk>(`/api/v1/admissions/sessions/${session}/applicants`),
  ]);
  const office = me.ok ? me.data.activeOffice : null;
  return (
    <Shell route="t/admissions" me={me.ok ? me.data : null}>
      {cycle.ok ? <Admissions cycle={cycle.data} actingOffice={office} /> : <ProblemNotice problem={cycle.problem} />}
      {desk.ok ? <ApplicantsDesk desk={desk.data} actingOffice={office} /> : <ProblemNotice problem={desk.problem} />}
      <Reconsiderations session={session} actingOffice={office} />
    </Shell>
  );
}
