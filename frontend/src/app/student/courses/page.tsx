import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import type { SpaceRow } from "@/lib/lms";
import { loadStudent } from "../load";
import { Courses } from "./Courses";

export const dynamic = "force-dynamic";

/** s/courses — the spaces the approved registrations open */
export default async function Page() {
  const loaded = await loadStudent();
  const c = loaded.student ? await api<{ session: string; spaces: SpaceRow[] }>("/api/v1/me/courses") : null;
  return (
    <Shell route="s/courses" me={loaded.me}>
      {loaded.student && c && c.ok ? <Courses session={c.data.session} spaces={c.data.spaces} /> : <ProblemNotice problem={c && !c.ok ? c.problem : loaded.student ? { status: 500, title: "Unreadable" } : loaded.problem} />}
    </Shell>
  );
}
