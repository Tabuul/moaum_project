import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import type { SpaceRow } from "@/lib/lms";
import { loadStudent } from "../load";
import { Courses } from "./Courses";
import { RegistrationHistory, type RegHistory } from "../registration-history/RegistrationHistory";
import { semesterText } from "@/lib/student-portal";

export const dynamic = "force-dynamic";

/** s/courses — the spaces the approved registrations open, then the full course-registration history */
export default async function Page() {
  const loaded = await loadStudent();
  const [c, h] = loaded.student
    ? await Promise.all([
        api<{ session: string; spaces: SpaceRow[] }>("/api/v1/me/courses"),
        api<RegHistory>("/api/v1/me/registration-history"),
      ])
    : [null, null];
  // the real session and semester of the spaces on show, not a fixed prototype label;
  // one semester → "2025/2026 · Semester: Second", a mix or none → just the session
  const sub = c && c.ok
    ? (() => {
        const sems = Array.from(new Set(c.data.spaces.map((s) => s.semester)));
        return sems.length === 1 ? `${c.data.session} · ${semesterText(sems[0])}` : c.data.session;
      })()
    : undefined;
  return (
    <Shell route="s/courses" me={loaded.me} sub={sub}>
      {loaded.student && c && c.ok ? <Courses session={c.data.session} spaces={c.data.spaces} /> : <ProblemNotice problem={c && !c.ok ? c.problem : loaded.student ? { status: 500, title: "Unreadable" } : loaded.problem} />}
      {loaded.student && h && h.ok ? (
        <div style={{ marginTop: "var(--s-6)" }}>
          <h2 className="phead__t mb-2">Course history</h2>
          <RegistrationHistory d={h.data} />
        </div>
      ) : null}
    </Shell>
  );
}
