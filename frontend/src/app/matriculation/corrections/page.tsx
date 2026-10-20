import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Correction, Place, StudentView } from "@/lib/matric-correction";
import { MatricCorrection } from "./MatricCorrection";

export const dynamic = "force-dynamic";

/** t/matriccorrection — V579: a matriculation number corrected, the old number kept: the student found by the current or a former
 *  number, the number the configuration gives, the correction checked and prepared by one officer and decided by another. */
export default async function MatricCorrectionPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const student = typeof p.student === "string" && /^[0-9a-f-]{36}$/i.test(p.student) ? p.student : null;
  const [me, places, list, view] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Place[]>("/api/v1/matriculation/corrections/places"),
    api<Correction[]>("/api/v1/matriculation/corrections"),
    student ? api<StudentView>(`/api/v1/matriculation/corrections/students/${student}`) : Promise.resolve(null),
  ]);
  const corrections = list.ok ? list.data : [];
  return (
    <Shell route="t/matriccorrection" me={me.ok ? me.data : null}>
      {list.ok
        ? <MatricCorrection places={places.ok ? places.data : []} corrections={corrections} office={me.ok ? me.data.activeOffice : null}
            me={me.ok ? me.data.actorId : null} initialView={view && view.ok ? view.data : null} />
        : <ProblemNotice problem={list.problem} />}
    </Shell>
  );
}
