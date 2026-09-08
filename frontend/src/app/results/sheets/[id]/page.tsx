import { api } from "@/lib/api";
import type { RollRow, SheetDetail } from "@/lib/results";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { ScoreEntry } from "./ScoreEntry";

export const dynamic = "force-dynamic";

/** t/sheet — one score sheet, the roll it is entered on, and the two numbers the lecturer types */
export default async function SheetPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const [me, detail, roll] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<SheetDetail>(`/api/v1/results/sheets/${id}`),
    api<RollRow[]>(`/api/v1/results/sheets/${id}/roll`),
  ]);
  return (
    <Shell route="t/sheet" me={me.ok ? me.data : null}>
      {detail.ok && roll.ok ? (
        <ScoreEntry detail={detail.data} roll={roll.data} actingOffice={me.ok ? me.data.activeOffice : null} />
      ) : (
        <ProblemNotice problem={!detail.ok ? detail.problem : !roll.ok ? roll.problem : { status: 500, title: "Unreadable" }} />
      )}
    </Shell>
  );
}
