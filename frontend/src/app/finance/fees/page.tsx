import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { FeeSchedule, type Schedule, type OpenReference } from "./FeeSchedule";

export const dynamic = "force-dynamic";

const SESSION_PATTERN = /^\d{4}\/\d{4}$/;

/** t/feesetup — the Bursar's desk: the session's charges, the clearance scheme, the references waiting to be confirmed */
export default async function FeesPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const requested = typeof params.session === "string" ? params.session : "2026/2027";
  const session = SESSION_PATTERN.test(requested) ? requested : "2026/2027";
  const [me, schedule, open, faculties] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Schedule>(`/api/v1/finance/sessions/${session}/schedule`),
    api<OpenReference[]>(`/api/v1/finance/references?session=${encodeURIComponent(session)}&state=open`),
    api<{ faculties: { code: string; name: string }[] }>("/api/v1/ref/structure"),
  ]);
  return (
    <Shell route="t/feesetup" me={me.ok ? me.data : null}>
      {schedule.ok ? (
        <FeeSchedule session={session} schedule={schedule.data} open={open.ok ? open.data : []} faculties={faculties.ok ? faculties.data.faculties : []} actingOffice={me.ok ? me.data.activeOffice : null} />
      ) : <ProblemNotice problem={schedule.problem} />}
    </Shell>
  );
}
