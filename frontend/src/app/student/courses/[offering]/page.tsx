import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import type { Space } from "@/lib/lms";
import { loadStudent } from "../../load";
import { SpaceScreen } from "./SpaceScreen";

export const dynamic = "force-dynamic";

/** one course space: the material, the assignments, the submission */
export default async function Page({ params }: { params: Promise<{ offering: string }> }) {
  const { offering } = await params;
  const loaded = await loadStudent();
  const s = loaded.student ? await api<Space>(`/api/v1/me/courses/${offering}`) : null;
  return (
    <Shell route="s/courses" me={loaded.me}>
      {loaded.student && s && s.ok ? <SpaceScreen s={s.data} /> : <ProblemNotice problem={s && !s.ok ? s.problem : loaded.student ? { status: 500, title: "Unreadable" } : loaded.problem} />}
    </Shell>
  );
}
