import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { MigrateApplicants } from "./MigrateApplicants";

export const dynamic = "force-dynamic";

const SESSION_PATTERN = /^\d{4}\/\d{4}$/;

interface FeeRule { session: string; stated: boolean; applicationFee: number; portalCharge: number; acceptanceFee: number }

export default async function MigratePage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const requested = typeof params.session === "string" ? params.session : "2026/2027";
  const session = SESSION_PATTERN.test(requested) ? requested : "2026/2027";
  const [me, fee] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<FeeRule>(`/api/v1/admissions/sessions/${session}/applicant-fees`),
  ]);
  return (
    <Shell route="t/migrate" me={me.ok ? me.data : null}>
      {fee.ok ? (
        <MigrateApplicants
          session={session}
          fee={{ stated: fee.data.stated, applicationFee: Number(fee.data.applicationFee), portalCharge: Number(fee.data.portalCharge) }}
          actingOffice={me.ok ? me.data.activeOffice : null}
        />
      ) : <ProblemNotice problem={fee.problem} />}
    </Shell>
  );
}
