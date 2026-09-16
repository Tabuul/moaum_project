import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Siwes, type Offering, type SiwesStudent, type Supervisor } from "./Siwes";

export const dynamic = "force-dynamic";

/** r/siwes — the HOD / SIWES Coordinator assigns a supervisor to each student and records the practical report. */
export default async function SiwesPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const [me, sessions] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<{ name: string; state: string }[]>("/api/v1/ref/sessions"),
  ]);
  const sessionList = sessions.ok ? sessions.data.map((s) => s.name) : [];
  const session = typeof p.session === "string" ? p.session
    : (sessions.ok ? sessions.data.find((s) => s.state === "CURRENT")?.name : null) ?? sessionList[0] ?? "2025/2026";
  const semester = typeof p.sem === "string" ? Number(p.sem) || 2 : 2;

  const offerings = await api<Offering[]>(`/api/v1/siwes/offerings?session=${encodeURIComponent(session)}&semester=${semester}`);
  const list = offerings.ok ? offerings.data : [];
  const offeringId = typeof p.offering === "string" ? p.offering : list[0]?.id ?? "";
  const [students, pool] = offeringId
    ? await Promise.all([
        api<SiwesStudent[]>(`/api/v1/siwes/offerings/${offeringId}/students`),
        api<Supervisor[]>(`/api/v1/siwes/offerings/${offeringId}/supervisors`),
      ])
    : [null, null];

  return (
    <Shell route="r/siwes" me={me.ok ? me.data : null}>
      {!offerings.ok ? (
        <ProblemNotice problem={offerings.problem} />
      ) : (
        <Siwes
          sessions={sessionList}
          session={session}
          semester={semester}
          offerings={list}
          offeringId={offeringId}
          students={students && students.ok ? students.data : []}
          pool={pool && pool.ok ? pool.data : []}
        />
      )}
    </Shell>
  );
}
