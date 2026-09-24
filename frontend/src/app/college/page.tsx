import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { Overview, type OverviewData } from "./Overview";

export const dynamic = "force-dynamic";

/** t/college — the College of Health Sciences overview: the live picture of the MBBS programme, and the doors to each desk */
export default async function CollegePage() {
  const [me, overview] = await Promise.all([api<Me>("/api/v1/iam/me"), api<OverviewData>("/api/v1/college/overview")]);
  return (
    <Shell route="t/college" me={me.ok ? me.data : null}>
      <Overview data={overview.ok ? overview.data : null} problem={overview.ok ? null : overview.problem} office={me.ok ? me.data.activeOffice : null} />
    </Shell>
  );
}
