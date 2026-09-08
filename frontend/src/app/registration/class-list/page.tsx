import { api } from "@/lib/api";
import { loadScope } from "@/lib/scope-data";
import type { ClassList } from "@/lib/results";
import { Shell, type Me } from "@/components/proto/Shell";
import { ClassListScreen } from "./ClassListScreen";
import { OfferingDesk, type DeskData } from "./OfferingDesk";

export const dynamic = "force-dynamic";

export default async function ClassListPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const { scope, structure, sessions } = await loadScope(params);
  const [me, courses] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<{ code: string; title: string; semester: number }[]>(`/api/v1/ref/courses${scope.dept ? `?dept=${encodeURIComponent(scope.dept)}` : ""}`),
  ]);
  const roll = scope.course
    ? await api<ClassList>(`/api/v1/registration/class-list?course=${encodeURIComponent(scope.course)}&session=${encodeURIComponent(scope.session)}&sem=${scope.sem || "1"}`)
    : null;
  /* the offering's own desk beside the roll (V027): the register, the timetable slots, the paper's slot */
  let desk: DeskData | null = null;
  if (roll && roll.ok) {
    const o = roll.data.offeringId;
    const [slots, attendance, examSlot] = await Promise.all([
      api<DeskData["slots"]>(`/api/v1/registration/offerings/${o}/slots`),
      api<DeskData["attendance"]>(`/api/v1/registration/offerings/${o}/attendance`),
      api<DeskData["examSlot"]>(`/api/v1/registration/offerings/${o}/exam-slot`),
    ]);
    desk = { slots: slots.ok ? slots.data : [], attendance: attendance.ok ? attendance.data : { days: [], students: [] }, examSlot: examSlot.ok ? examSlot.data : {} };
  }
  return (
    <Shell route="r/classlist" me={me.ok ? me.data : null}>
      <ClassListScreen scope={scope} structure={structure} sessions={sessions} courses={courses.ok ? courses.data : []} roll={roll && roll.ok ? roll.data : null} problem={roll && !roll.ok ? roll.problem : null} />
      {roll && roll.ok && desk ? <OfferingDesk roll={roll.data} desk={desk} actingOffice={me.ok ? me.data.activeOffice : null} /> : null}
    </Shell>
  );
}
