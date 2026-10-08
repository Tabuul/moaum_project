import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { CbtCourses, type CbtCoursePage } from "./CbtCourses";

export const dynamic = "force-dynamic";

/** t/cbtcourses — which courses the University examines by CBT (V364): no course is assumed to be one */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const q = await searchParams;
  const p = new URLSearchParams();
  for (const k of ["q", "enabled", "level", "page"]) if (typeof q[k] === "string" && q[k]) p.set(k, String(q[k]));
  const [me, data] = await Promise.all([api<Me>("/api/v1/iam/me"), api<CbtCoursePage>(`/api/v1/cbt/catalogue?${p.toString()}`)]);
  return (
    <Shell route="t/cbtcourses" me={me.ok ? me.data : null}>
      {data.ok ? <CbtCourses data={data.data} query={{ q: typeof q.q === "string" ? q.q : "", enabled: typeof q.enabled === "string" ? q.enabled : "", level: typeof q.level === "string" ? q.level : "" }} /> : <ProblemNotice problem={data.problem} />}
    </Shell>
  );
}
