import { api } from "@/lib/api";
import type { ReadyQueue } from "@/lib/clearance";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { ReadyToGraduate } from "./ReadyToGraduate";

export const dynamic = "force-dynamic";

/** t/readytograduate — V668: the Bursar's queue of final clearances that wait only on the Bursary's confirmation, whose confirmation
 *  graduates the student; ?q= narrows it. */
export default async function ReadyToGraduatePage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const q = typeof p.q === "string" ? p.q.trim() : "";
  const [me, queue] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<ReadyQueue>(`/api/v1/clearance/ready-to-graduate${q ? `?${new URLSearchParams({ q }).toString()}` : ""}`),
  ]);
  return (
    <Shell route="t/readytograduate" me={me.ok ? me.data : null}>
      {queue.ok ? <ReadyToGraduate queue={queue.data} q={q} /> : <ProblemNotice problem={queue.problem} />}
    </Shell>
  );
}
