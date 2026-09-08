import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import { loadStudent } from "../load";

export const dynamic = "force-dynamic";
import type { Timetable } from "@/lib/student-portal";
import { TimetableScreen } from "../Screens5";

/** s/timetable — the slots the department gave */
export default async function Page() {
  const loaded = await loadStudent();
  if (!loaded.student) return <Shell route="s/timetable" me={loaded.me}><ProblemNotice problem={loaded.problem} /></Shell>;
  const d = await api<Timetable>("/api/v1/me/timetable");
  return (
    <Shell route="s/timetable" me={loaded.me}>
      {d.ok ? <TimetableScreen t={d.data} /> : <ProblemNotice problem={d.problem} />}
    </Shell>
  );
}
