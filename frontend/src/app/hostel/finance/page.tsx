import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { hostelSession } from "../page";
import { HostelFinance, type FeesData, type FinanceData } from "./Finance";

export const dynamic = "force-dynamic";

/** t/hostel-finance — the Bursar's hostel figures, the fee rules and every occupant's fee line (V290) */
export default async function HostelFinancePage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const { session, sessions } = await hostelSession(p);
  const [me, data, fees] = await Promise.all([api<Me>("/api/v1/iam/me"), api<FinanceData>(`/api/v1/hostel/sessions/${session}/finance`), api<FeesData>(`/api/v1/hostel/sessions/${session}/fees`)]);
  return (
    <Shell route="t/hostel-finance" me={me.ok ? me.data : null}>
      {data.ok && fees.ok ? <HostelFinance data={data.data} fees={fees.data} session={session} sessions={sessions} office={me.ok ? me.data.activeOffice ?? null : null} /> : <ProblemNotice problem={data.ok ? (fees.ok ? { status: 500, title: "Unreadable" } : fees.problem) : data.problem} />}
    </Shell>
  );
}
