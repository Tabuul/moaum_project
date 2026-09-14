import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Payments, type PaymentsData, type Filters } from "./Payments";

export const dynamic = "force-dynamic";

const str = (v: string | string[] | undefined) => (typeof v === "string" && v.trim() ? v.trim() : "");

/** t/payments — the Bursary's payments query. */
export default async function PaymentsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const f: Filters = {
    session: str(p.session), faculty: str(p.faculty), dept: str(p.dept), programme: str(p.programme),
    level: str(p.level), category: str(p.category), channel: str(p.channel), from: str(p.from), to: str(p.to),
  };
  const q = new URLSearchParams();
  for (const [k, v] of Object.entries(f)) if (v) q.set(k, v);
  const [me, data] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<PaymentsData>(`/api/v1/finance/payments${q.toString() ? `?${q}` : ""}`),
  ]);
  return (
    <Shell route="t/payments" me={me.ok ? me.data : null}>
      {data.ok ? <Payments d={data.data} filters={f} /> : <ProblemNotice problem={data.problem} />}
    </Shell>
  );
}
