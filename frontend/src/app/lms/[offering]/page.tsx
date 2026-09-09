import { api } from "@/lib/api";
import type { Desk } from "@/lib/lms";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { CourseSpaceDesk } from "./CourseSpaceDesk";

export const dynamic = "force-dynamic";

/** one course space from the lecturer's side: materials, assignments, the gradebook, engagement */
export default async function SpacePage({ params, searchParams }: { params: Promise<{ offering: string }>; searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const { offering } = await params;
  const q = await searchParams;
  const [me, d] = await Promise.all([api<Me>("/api/v1/iam/me"), api<Desk>(`/api/v1/lms/offerings/${offering}`)]);
  const upload = q.tab === "upload";
  return (
    <Shell route={upload ? "r/upload" : "t/lms"} me={me.ok ? me.data : null}>
      {d.ok ? <CourseSpaceDesk d={d.data} upload={upload} /> : <ProblemNotice problem={d.problem} />}
    </Shell>
  );
}
