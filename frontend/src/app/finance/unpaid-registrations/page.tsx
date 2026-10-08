import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { UnpaidRegistrations, type UnpaidView } from "./UnpaidRegistrations";

export const dynamic = "force-dynamic";

/** /finance/unpaid-registrations — V362: the session's course registrations made without the semester's school fees
 *  cleared (not stated for the student, or not paid), read for the Bursary and the Registry to act on */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const session = typeof p.session === "string" ? p.session : "";
  const [me, view] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<UnpaidView>(`/api/v1/finance/registrations-without-fees${session ? `?session=${encodeURIComponent(session)}` : ""}`),
  ]);
  return (
    <Shell route="t/unpaidreg" me={me.ok ? me.data : null}>
      {view.ok ? <UnpaidRegistrations view={view.data} /> : <ProblemNotice problem={view.problem} />}
    </Shell>
  );
}
