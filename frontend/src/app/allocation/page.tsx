import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { AllocationDesk, type DeskOptions } from "./AllocationDesk";
import type { ImportRecord } from "../allocate/BulkUpload";

export const dynamic = "force-dynamic";

/** t/allocation — course allocation from the Director of ICT's and the ICT Support Desk's dashboards (V408): the University's
 *  classes, or a CPO's posting's, worked through the one allocation engine every desk uses. */
export default async function AllocationPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const s = (k: string) => (typeof p[k] === "string" ? (p[k] as string) : "");
  const [me, options] = await Promise.all([api<Me>("/api/v1/iam/me"), api<DeskOptions>("/api/v1/allocation/desk/options")]);
  const imports = options.ok && options.data.capabilities.includes("BULK_ALLOCATE")
    ? await api<ImportRecord[]>("/api/v1/allocation/imports?limit=50").then((r) => (r.ok ? r.data : []))
    : [];
  return (
    <Shell route="t/allocation" me={me.ok ? me.data : null}>
      {!options.ok ? <ProblemNotice problem={options.problem} /> : (
        <AllocationDesk options={options.data} imports={imports}
          initial={{ session: s("session"), semester: Number(s("sem")) || 0, faculty: s("faculty"), dept: s("dept"), programme: s("programme"),
                     level: Number(s("level")) || 0, status: s("status"), q: s("q"), ticket: s("ticket") }} />
      )}
    </Shell>
  );
}
