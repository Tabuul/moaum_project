import { api } from "@/lib/api";
import type { ChangeQueue } from "@/lib/student";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { BiodataChanges } from "./BiodataChanges";

export const dynamic = "force-dynamic";

const STATES = ["PENDING", "EVIDENCE_ASKED", "APPROVED", "REFUSED"];

export default async function BiodataChangesPage({
  searchParams,
}: {
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const params = await searchParams;
  const asked = typeof params.state === "string" ? params.state.toUpperCase() : "";
  const state = STATES.includes(asked) ? asked : "";

  const [me, queue] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<ChangeQueue>(`/api/v1/student/biodata-changes${state ? `?state=${state}` : ""}`),
  ]);

  return (
    <Shell route="t/biochange" me={me.ok ? me.data : null}>
      {!queue.ok ? (
        <ProblemNotice problem={queue.problem} />
      ) : (
        <BiodataChanges queue={queue.data} state={state} actingOffice={me.ok ? me.data.activeOffice : null} />
      )}
    </Shell>
  );
}
