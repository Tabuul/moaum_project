import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { HeldOwing, type HeldOwingRow } from "./HeldOwing";

export const dynamic = "force-dynamic";

/** t/heldscripts — the students a held script is waiting on, and what they owe (V240) */
export default async function HeldScriptsPage() {
  const [me, d] = await Promise.all([api<Me>("/api/v1/iam/me"), api<HeldOwingRow[]>("/api/v1/results/held/owing")]);
  return (
    <Shell route="t/heldscripts" me={me.ok ? me.data : null}>
      {d.ok ? <HeldOwing rows={d.data} /> : <ProblemNotice problem={d.problem} />}
    </Shell>
  );
}
