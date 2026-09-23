import { api } from "@/lib/api";
import type { RollRow, SheetDetail } from "@/lib/results";
import { semesterName } from "@/lib/student-portal";

/** the API leaves a null field out of the JSON; the screen tests these against null, so put them back */
function normalise(r: RollRow): RollRow {
  return { ...r, ca: r.ca ?? null, exam: r.exam ?? null, total: r.total ?? null, grade: r.grade ?? null, points: r.points ?? null, outcome: r.outcome ?? null, version: r.version ?? null };
}
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
  const s = detail.ok ? detail.data.sheet : null;
  return (
    <Shell route="t/sheet" me={me.ok ? me.data : null}
      title={s ? `${s.courseCode} — ${s.courseTitle}` : undefined}
      sub={s ? `${s.units} credit unit${s.units === 1 ? "" : "s"} · ${s.session} ${semesterName(s.semester).toLowerCase()} semester · ${s.deptName} · every registered candidate, all programmes` : undefined}>
      {detail.ok && roll.ok ? (
        <ScoreEntry detail={detail.data} roll={roll.data.map(normalise)} actingOffice={me.ok ? me.data.activeOffice : null} />
      ) : (
        <ProblemNotice problem={!detail.ok ? detail.problem : !roll.ok ? roll.problem : { status: 500, title: "Unreadable" }} />
      )}
    </Shell>
  );
}
