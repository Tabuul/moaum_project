import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Campaigns, type CampaignsPage } from "./Campaigns";

export const dynamic = "force-dynamic";

/** t/campaigns — a message to many (V426): the NEW PORTAL MIGRATION welcome, an announcement to a faculty, a department, a
 *  level, a session, the staff or the applicants; previewed, tested, sent as a job, reported. */
export default async function CampaignsRoute({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const q = await searchParams;
  const open = Array.isArray(q.open) ? q.open[0] : q.open;
  const [me, page] = await Promise.all([api<Me>("/api/v1/iam/me"), api<CampaignsPage>("/api/v1/notices/campaigns")]);
  return (
    <Shell route="t/campaigns" me={me.ok ? me.data : null}>
      {page.ok ? <Campaigns d={page.data} actingOffice={me.ok ? me.data.activeOffice : null} open={open ?? null} /> : <ProblemNotice problem={page.problem} />}
    </Shell>
  );
}
