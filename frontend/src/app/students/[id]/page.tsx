import { cookies } from "next/headers";
import { api } from "@/lib/api";
import { readScope, SCOPE_COOKIE } from "@/lib/scope";
import type { StudentRecord } from "@/lib/student";
import type { Me as Portal } from "@/lib/student-portal";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Student360 } from "./Student360";

export const dynamic = "force-dynamic";

export default async function StudentPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const { id } = await params;
  const scope = readScope(await searchParams, (await cookies()).get(SCOPE_COOKIE)?.value);

  /* V360: the student's own figures — the session's school fees (for the offices that read them) and the CGPA from the
     published results — as the student sees them, beside the record */
  const [me, record, portal] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<StudentRecord>(`/api/v1/student/students/${id}?session=${encodeURIComponent(scope.session)}`),
    api<Portal>(`/api/v1/student/students/${id}/portal`),
  ]);

  return (
    <Shell route="t/student" me={me.ok ? me.data : null}>
      {!record.ok ? (
        <ProblemNotice problem={record.problem} />
      ) : (
        <Student360 record={record.data} portal={portal.ok ? portal.data : null} session={scope.session} actingOffice={me.ok ? me.data.activeOffice : null} />
      )}
    </Shell>
  );
}
