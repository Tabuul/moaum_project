import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import { loadStudent } from "../load";

export const dynamic = "force-dynamic";
import type { Fees } from "@/lib/student-portal";
import { FeesScreen } from "../Screens2";

/** s/fees — the charge computed from the schedule, the payments, and what the scheme releases */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const q = await searchParams;
  const loaded = await loadStudent();
  if (!loaded.student) return <Shell route="s/fees" me={loaded.me}><ProblemNotice problem={loaded.problem} /></Shell>;
  const session = typeof q.session === "string" && /^\d{4}\/\d{4}$/.test(q.session) ? q.session : loaded.student.session;
  // on return from the gateway, verify with the gateway and confirm at once — no Bursary step, no wait for a webhook
  if (typeof q.paid === "string" && q.paid) {
    await api("/api/v1/payments/verify", { method: "POST", body: { reference: q.paid }, reason: `Verify payment ${q.paid}` });
  }
  const fees = await api<Fees>(`/api/v1/me/fees?session=${encodeURIComponent(session)}`);
  return (
    <Shell route="s/fees" me={loaded.me}>
      {fees.ok ? <FeesScreen s={loaded.student} fees={fees.data} paid={typeof q.paid === "string" ? q.paid : null} /> : <ProblemNotice problem={fees.problem} />}
    </Shell>
  );
}
