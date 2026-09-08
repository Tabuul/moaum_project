import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { AdmissionSettings, type AdmissionPolicy, type PolicySummary } from "./AdmissionSettings";

export const dynamic = "force-dynamic";

const SESSION_PATTERN = /^\d{4}\/\d{4}$/;

function previous(session: string): string {
  const [a, b] = session.split("/").map(Number);
  return `${a - 1}/${b - 1}`;
}

export default async function AdmissionSettingsPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const params = await searchParams;
  const requested = typeof params.session === "string" ? params.session : "2026/2027";
  const session = SESSION_PATTERN.test(requested) ? requested : "2026/2027";
  const prev = previous(session);

  const [me, policy, previousPolicy, policies] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<AdmissionPolicy>(`/api/v1/admissions/sessions/${session}/policy`),
    api<AdmissionPolicy>(`/api/v1/admissions/sessions/${prev}/policy`),
    api<PolicySummary[]>("/api/v1/admissions/policies"),
  ]);
  const loadCutoff = await api<{ cutoff: number | null }>(`/api/v1/admissions/sessions/${session}/load-cutoff`);

  return (
    <Shell route="t/admissionsetup" me={me.ok ? me.data : null}>
      <AdmissionSettings
        session={session}
        policy={policy.ok ? policy.data : null}
        policyProblem={policy.ok || policy.problem.status === 404 ? null : policy.problem}
        previous={previousPolicy.ok ? previousPolicy.data : null}
        previousSession={prev}
        sessions={policies.ok ? policies.data : []}
        actingOffice={me.ok ? me.data.activeOffice : null}
        loadCutoff={loadCutoff.ok ? loadCutoff.data.cutoff : null}
      />
    </Shell>
  );
}
