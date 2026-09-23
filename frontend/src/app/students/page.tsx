import { api } from "@/lib/api";
import { scopeQuery } from "@/lib/scope";
import { loadScope } from "@/lib/scope-data";
import type { Register } from "@/lib/student";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Students } from "./Students";
import { MigratedPanel, type MigratedSummary } from "./MigratedPanel";

export const dynamic = "force-dynamic";

export default async function StudentsPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const params = await searchParams;
  // loadScope pins the scope to the office's own faculty/department (a HOD is bound to theirs)
  // before the register is read, so the register comes back within that scope.
  const { scope, structure, sessions, ceiling } = await loadScope(params);
  const q = typeof params.q === "string" ? params.q : "";

  const [me, register, migrated] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Register>(`/api/v1/student/students?${scopeQuery(scope)}&q=${encodeURIComponent(q)}`),
    api<MigratedSummary>("/api/v1/student/students/migrated?from=100&to=400"),
  ]);
  const office = me.ok ? me.data.activeOffice : null;
  const mayClear = office === "registrar" || office === "dregistrar" || office === "academic" || office === "ict" || office === "super";

  return (
    <Shell route="t/students" me={me.ok ? me.data : null}>
      {!register.ok ? (
        <ProblemNotice problem={register.problem} />
      ) : (
        <>
        {mayClear && migrated.ok ? <MigratedPanel summary={migrated.data} /> : null}
        <Students
          scope={scope}
          q={q}
          register={register.data}
          structure={structure}
          sessions={sessions}
          ceiling={ceiling}
        />
        </>
      )}
    </Shell>
  );
}
