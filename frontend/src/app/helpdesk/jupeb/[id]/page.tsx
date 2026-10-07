import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { JupebSupport, type JupebSupportData } from "./JupebSupport";

export const dynamic = "force-dynamic";

/** One JUPEB record in support mode (V347): what the agent's JUPEB postings allow, every act on the support ledger and the candidate's ticket. */
export default async function Page({ params, searchParams }: { params: Promise<{ id: string }>; searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const { id } = await params;
  const p = await searchParams;
  const ticket = typeof p.ticket === "string" ? p.ticket : "";
  const tab = typeof p.tab === "string" ? p.tab : "record";
  const [me, data] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<JupebSupportData>(`/api/v1/helpdesk/support/jupeb/${id}${ticket ? `?ticket=${encodeURIComponent(ticket)}` : ""}`),
  ]);
  return (
    <Shell route="t/supportjupeb" me={me.ok ? me.data : null}>
      {!data.ok ? <ProblemNotice problem={data.problem} /> : <JupebSupport id={id} data={data.data} tab={tab} />}
    </Shell>
  );
}
