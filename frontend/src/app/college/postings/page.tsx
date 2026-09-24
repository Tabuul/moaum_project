import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Postings, type Allocation, type CollegeStructure, type CollegeStudent, type Supervisor } from "./Postings";

export const dynamic = "force-dynamic";

/** t/postings — the postings desk: the College's students at a level allocated to a block's postings for a session */
export default async function PostingsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const [me, structure, sessions, supervisors] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<CollegeStructure>("/api/v1/college/structure"),
    api<{ name: string; state?: string }[]>("/api/v1/ref/sessions"),
    api<Supervisor[]>("/api/v1/college/supervisors"),
  ]);
  const sessionList = sessions.ok ? sessions.data : [];
  const current = sessionList.find((s) => s.state === "CURRENT")?.name ?? sessionList[0]?.name ?? "";
  const session = typeof p.session === "string" && p.session ? p.session : current;
  const level = typeof p.level === "string" && p.level ? Number(p.level) : 400;
  const posting = typeof p.posting === "string" ? p.posting : "";
  const [students, allocations] = await Promise.all([
    session ? api<CollegeStudent[]>(`/api/v1/college/students?session=${encodeURIComponent(session)}&level=${level}`) : null,
    session && posting ? api<Allocation[]>(`/api/v1/college/postings/${encodeURIComponent(posting)}/allocations?session=${encodeURIComponent(session)}`) : null,
  ]);
  return (
    <Shell route="t/postings" me={me.ok ? me.data : null}>
      {!structure.ok ? <ProblemNotice problem={structure.problem} /> : (
        <Postings
          structure={structure.data}
          sessions={sessionList.map((s) => s.name)}
          session={session}
          level={level}
          posting={posting}
          students={students && students.ok ? students.data : []}
          allocations={allocations && allocations.ok ? allocations.data : []}
          supervisors={supervisors.ok ? supervisors.data : []}
          problem={students && !students.ok ? students.problem : allocations && !allocations.ok ? allocations.problem : null}
        />
      )}
    </Shell>
  );
}
