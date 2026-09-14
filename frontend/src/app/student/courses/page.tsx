import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import type { SpaceRow } from "@/lib/lms";
import { loadStudent } from "../load";
import { Courses } from "./Courses";
import { RegistrationHistory, type RegHistory } from "../registration-history/RegistrationHistory";

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
  return (
    <Shell route="s/courses" me={loaded.me}>
      {loaded.student && c && c.ok ? <Courses session={c.data.session} spaces={c.data.spaces} /> : <ProblemNotice problem={c && !c.ok ? c.problem : loaded.student ? { status: 500, title: "Unreadable" } : loaded.problem} />}
      {loaded.student && h && h.ok ? (
        <div style={{ marginTop: 22 }}>
          <h2 style={{ fontSize: 17, fontWeight: 700, margin: "0 0 10px" }}>Course history</h2>
          <RegistrationHistory d={h.data} />
        </div>
      ) : null}
    </Shell>
  );
}
