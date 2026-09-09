import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Allocate, type Offering, type Lecturer, type Dept } from "./Allocate";

export const dynamic = "force-dynamic";

/** r/allocate — the Head of Department assigns a lecturer and second examiner to each offering. */
export default async function AllocatePage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const [me, depts, sessions] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Dept[]>("/api/v1/allocation/departments"),
    api<{ name: string; state: string }[]>("/api/v1/ref/sessions"),
  ]);
  const deptList = depts.ok ? depts.data : [];
  const sessionList = sessions.ok ? sessions.data.map((s) => s.name) : [];
  const dept = typeof p.dept === "string" ? p.dept : deptList[0]?.code ?? "";
  const session = typeof p.session === "string" ? p.session : (sessions.ok ? sessions.data.find((s) => s.state === "CURRENT")?.name : null) ?? sessionList[0] ?? "2026/2027";
  const semester = typeof p.sem === "string" ? Number(p.sem) || 1 : 1;

  const [offerings, lecturers] = dept
    ? await Promise.all([
        api<Offering[]>(`/api/v1/allocation?dept=${encodeURIComponent(dept)}&session=${encodeURIComponent(session)}&semester=${semester}`),
        api<Lecturer[]>(`/api/v1/allocation/lecturers?dept=${encodeURIComponent(dept)}&session=${encodeURIComponent(session)}&semester=${semester}`),
      ])
    : [null, null];

  return (
    <Shell route="r/allocate" me={me.ok ? me.data : null}>
      {!depts.ok ? (
        <ProblemNotice problem={depts.problem} />
      ) : (
        <Allocate
          depts={deptList}
          sessions={sessionList}
          dept={dept}
          session={session}
          semester={semester}
          offerings={offerings && offerings.ok ? offerings.data : []}
          lecturers={lecturers && lecturers.ok ? lecturers.data : []}
          problem={offerings && !offerings.ok ? offerings.problem : null}
        />
      )}
    </Shell>
  );
}
