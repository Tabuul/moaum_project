import { api } from "@/lib/api";
import type { Overview, Workflows } from "@/lib/clearance";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { ClearanceManage } from "./ClearanceManage";

export const dynamic = "force-dynamic";

/** t/clearancemanage — clearance management (V415): the Registry's overview of fresh and final clearance office by office,
 *  starting the eligible students, and the workflows' stages, order and conditions. */
export default async function ClearanceManagePage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const s = (k: string) => (typeof params[k] === "string" ? (params[k] as string).trim() : "");
  const [me, wf] = await Promise.all([api<Me>("/api/v1/iam/me"), api<Workflows>("/api/v1/clearance/workflows")]);
  if (!wf.ok) return <Shell route="t/clearancemanage" me={me.ok ? me.data : null}><ProblemNotice problem={wf.problem} /></Shell>;
  const workflow = (wf.data.workflows.find((w) => w.code === s("wf").toUpperCase()) ?? wf.data.workflows[0]).code;
  const session = s("session") || wf.data.currentSession || wf.data.sessions[0] || "";
  const overview = session ? await api<Overview>(`/api/v1/clearance/overview?${new URLSearchParams({ workflow, session }).toString()}`) : null;
  return (
    <Shell route="t/clearancemanage" me={me.ok ? me.data : null}>
      {overview && !overview.ok ? <ProblemNotice problem={overview.problem} /> : null}
      <ClearanceManage workflows={wf.data} workflow={workflow} session={session} overview={overview && overview.ok ? overview.data : null} />
    </Shell>
  );
}
