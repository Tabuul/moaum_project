import { api } from "@/lib/api";
import type { ClinicDesk } from "@/lib/health";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Clinic } from "./Clinic";

export const dynamic = "force-dynamic";

/** t/clinic — the waiting list, the record opened by the clinician, the outcome */
export default async function ClinicPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const number = typeof params.number === "string" ? params.number : "";
  const [me, desk] = await Promise.all([api<Me>("/api/v1/iam/me"), api<ClinicDesk>(`/api/v1/health/desk${number ? `?number=${encodeURIComponent(number)}` : ""}`)]);
  return (
    <Shell route="t/clinic" me={me.ok ? me.data : null}>
      {desk.ok ? <Clinic d={desk.data} number={number} /> : <ProblemNotice problem={desk.problem} />}
    </Shell>
  );
}
