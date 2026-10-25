import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { ProposalView } from "./ProposalView";
import type { DeskData } from "../ptn-call";
import "../partnerships.css";

export const dynamic = "force-dynamic";

/** One partnership proposal on a page of its own (V658). The API holds every office to what it may see, so an id typed into the
 *  address bar for a proposal outside the office's reach reads as not found, and nothing of it is shown. */
export default async function PartnershipRoute({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const [me, desk] = await Promise.all([api<Me>("/api/v1/iam/me"), api<DeskData>("/api/v1/partnerships/desk")]);
  return (
    <Shell route="t/partnerships" me={me.ok ? me.data : null}>
      {desk.ok ? <ProposalView id={id} desk={desk.data} /> : <ProblemNotice problem={desk.problem} />}
    </Shell>
  );
}
