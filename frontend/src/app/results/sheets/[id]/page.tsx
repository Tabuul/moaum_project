import { api } from "@/lib/api";
import type { HeldScript, RollRow, SheetDetail } from "@/lib/results";
import { HeldScripts } from "./HeldScripts";
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
  const [me, detail, roll, held] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<SheetDetail>(`/api/v1/results/sheets/${id}`),
    api<RollRow[]>(`/api/v1/results/sheets/${id}/roll`),
    api<Record<string, unknown>[]>(`/api/v1/results/sheets/${id}/held`),
  ]);
  // the API's rows are snake_case and leave nulls out; the panel wants camelCase with nulls in place
  const heldRows: HeldScript[] = held.ok ? held.data.map((h) => ({
    id: String(h.id), studentId: String(h.student_id), number: String(h.number ?? ""), surname: String(h.surname ?? ""), otherNames: String(h.other_names ?? ""),
    programmeName: String(h.programme_name ?? ""), level: Number(h.level ?? 0), ca: h.ca == null ? null : Number(h.ca), exam: h.exam == null ? null : Number(h.exam),
    outcome: String(h.outcome ?? "GRADED"), note: h.note == null ? null : String(h.note), state: String(h.state ?? "HELD"),
    enteredBy: h.entered_by == null ? null : String(h.entered_by), enteredAt: String(h.entered_at ?? ""), releasedAt: h.released_at == null ? null : String(h.released_at),
    lapsedAt: h.lapsed_at == null ? null : String(h.lapsed_at), closesOn: h.closes_on == null ? null : String(h.closes_on),
  })) : [];
  const office = me.ok ? me.data.activeOffice : null;
  const own = office === "lecturer" || office === "exams" || office === "academic";
  const s = detail.ok ? detail.data.sheet : null;
  return (
    <Shell route="t/sheet" me={me.ok ? me.data : null}
      title={s ? `${s.courseCode} — ${s.courseTitle}` : undefined}
      sub={s ? `${s.units} credit unit${s.units === 1 ? "" : "s"} · ${s.session} ${semesterName(s.semester).toLowerCase()} semester · ${s.deptName} · every registered candidate, all programmes` : undefined}>
      {detail.ok && roll.ok ? (
        <>
          <ScoreEntry detail={detail.data} roll={roll.data.map(normalise)} actingOffice={office} />
          <HeldScripts sheetId={s!.id} courseCode={s!.courseCode} caMax={typeof s!.caMax === "number" ? s!.caMax : 40} items={heldRows} own={own}
            closesOn={heldRows[0]?.closesOn ?? null} />
        </>
      ) : (
        <ProblemNotice problem={!detail.ok ? detail.problem : !roll.ok ? roll.problem : { status: 500, title: "Unreadable" }} />
      )}
    </Shell>
  );
}
