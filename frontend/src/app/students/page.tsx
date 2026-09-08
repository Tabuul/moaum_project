import { cookies } from "next/headers";
import { api } from "@/lib/api";
import { readScope, scopeQuery, SCOPE_COOKIE } from "@/lib/scope";
import type { Register, RefSession } from "@/lib/student";
import { Shell, type Me } from "@/components/proto/Shell";
import type { ScopeStructure } from "@/components/proto/ScopeBar";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Students } from "./Students";

export const dynamic = "force-dynamic";

export default async function StudentsPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const params = await searchParams;
  const scope = readScope(params, (await cookies()).get(SCOPE_COOKIE)?.value);
  const q = typeof params.q === "string" ? params.q : "";

  const [me, register, structure, sessions] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Register>(`/api/v1/student/students?${scopeQuery(scope)}&q=${encodeURIComponent(q)}`),
    api<ScopeStructure>("/api/v1/ref/structure"),
    api<RefSession[]>("/api/v1/ref/sessions"),
  ]);

  return (
    <Shell route="t/students" me={me.ok ? me.data : null}>
      {!register.ok ? (
        <ProblemNotice problem={register.problem} />
      ) : (
        <Students
          scope={scope}
          q={q}
          register={register.data}
          structure={structure.ok ? structure.data : { faculties: [] }}
          sessions={sessions.ok ? sessions.data.map((s) => s.name) : [scope.session]}
        />
      )}
    </Shell>
  );
}
