import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { FeeSchedule, type Schedule, type OpenReference, type FeeGroup, type ProgrammeOption, type ApplicantFees, type FeeItem } from "./FeeSchedule";

export const dynamic = "force-dynamic";

const SESSION_PATTERN = /^\d{4}\/\d{4}$/;

/** t/feesetup — the Bursar's desk: the session's charges, the clearance scheme, the references waiting to be confirmed */
export default async function FeesPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  // No explicit ?session= lands on the CURRENT session — never a hardcoded year, so an
  // upload does not silently go to the wrong session (the cause of the 2026/2027 mix-up).
  const explicit = typeof params.session === "string" && SESSION_PATTERN.test(params.session) ? params.session : null;
  const sessionsRes = await api<{ name: string; state: string }[]>("/api/v1/ref/sessions");
  const current = sessionsRes.ok ? sessionsRes.data.find((s) => s.state === "CURRENT")?.name ?? null : null;
  const session = explicit ?? current ?? "2026/2027";
  const [me, schedule, open, faculties, feeGroups, programmes, applicantFees, feeItems] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Schedule>(`/api/v1/finance/sessions/${session}/schedule`),
    api<OpenReference[]>(`/api/v1/finance/references?session=${encodeURIComponent(session)}&state=open`),
    api<{ faculties: { code: string; name: string }[] }>("/api/v1/ref/structure"),
    api<FeeGroup[]>("/api/v1/finance/fee-groups"),
    api<ProgrammeOption[]>("/api/v1/finance/programmes"),
    api<ApplicantFees>(`/api/v1/admissions/sessions/${session}/applicant-fees`),
    api<FeeItem[]>("/api/v1/finance/fee-items"),
  ]);
  const sessions = sessionsRes;
  return (
    <Shell route="t/feesetup" me={me.ok ? me.data : null}>
      {schedule.ok ? (
        <FeeSchedule
          session={session}
          schedule={schedule.data}
          open={open.ok ? open.data : []}
          faculties={faculties.ok ? faculties.data.faculties : []}
          feeGroups={feeGroups.ok ? feeGroups.data : []}
          programmes={programmes.ok ? programmes.data : []}
          applicantFees={applicantFees.ok ? applicantFees.data : null}
          feeItems={feeItems.ok ? feeItems.data : []}
          sessions={sessions.ok ? sessions.data.map((s) => s.name) : [session]}
          actingOffice={me.ok ? me.data.activeOffice : null}
        />
      ) : <ProblemNotice problem={schedule.problem} />}
    </Shell>
  );
}
