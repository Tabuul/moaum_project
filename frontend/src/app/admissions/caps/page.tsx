import { api } from "@/lib/api";
import type { Programme } from "@/lib/caps";
import { Shell, type Me } from "@/components/proto/Shell";
import type { ScopeStructure } from "@/components/proto/ScopeBar";
import { ProblemNotice } from "@/components/ProblemNotice";
import { CapsIntake, type AdmissionPolicy, type CapsBatch, type Finding } from "./CapsIntake";

export const dynamic = "force-dynamic";

const SESSION_PATTERN = /^\d{4}\/\d{4}$/;

export default async function CapsIntakePage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const params = await searchParams;
  const requested = typeof params.session === "string" ? params.session : "2026/2027";
  const session = SESSION_PATTERN.test(requested) ? requested : "2026/2027";

  const [me, structure, programmes, batches, reconciliation, policy] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<ScopeStructure>("/api/v1/ref/structure"),
    api<Programme[]>("/api/v1/admissions/programmes"),
    api<CapsBatch[]>(`/api/v1/admissions/caps-batches?session=${encodeURIComponent(session)}`),
    api<Finding[]>(`/api/v1/admissions/sessions/${session}/reconciliation`),
    api<AdmissionPolicy>(`/api/v1/admissions/sessions/${session}/policy`),
  ]);

  return (
    <Shell route="t/capsintake" me={me.ok ? me.data : null}>
      {!programmes.ok ? (
        <ProblemNotice problem={programmes.problem} />
      ) : (
        <CapsIntake
          session={session}
          programmes={programmes.data}
          batches={batches.ok ? batches.data : []}
          batchesProblem={batches.ok ? null : batches.problem}
          reconciliation={reconciliation.ok ? reconciliation.data : []}
          policy={policy.ok ? policy.data : null}
          policyProblem={policy.ok ? null : policy.problem}
          actingOffice={me.ok ? me.data.activeOffice : null}
          today={new Date().toISOString().slice(0, 10)}
          departments={structure.ok ? structure.data.faculties.flatMap((f) => f.departments.map((d) => ({ code: d.code, name: d.name, facultyName: f.name }))) : []}
        />
      )}
    </Shell>
  );
}
