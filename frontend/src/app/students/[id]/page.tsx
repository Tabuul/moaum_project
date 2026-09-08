import { cookies } from "next/headers";
import { api } from "@/lib/api";
import { readScope, SCOPE_COOKIE } from "@/lib/scope";
import type { StudentRecord } from "@/lib/student";
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

  const [me, record] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<StudentRecord>(`/api/v1/student/students/${id}?session=${encodeURIComponent(scope.session)}`),
  ]);

  return (
    <Shell route="t/student" me={me.ok ? me.data : null}>
      {!record.ok ? (
        <ProblemNotice problem={record.problem} />
      ) : (
        <Student360 record={record.data} session={scope.session} actingOffice={me.ok ? me.data.activeOffice : null} />
      )}
    </Shell>
  );
}
