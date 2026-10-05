import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { CourseList, Directory } from "@/lib/catalogue";
import { AllCourses, type Filters } from "./AllCourses";

export const dynamic = "force-dynamic";

/** Every course within the office's scope, with the programmes that offer it — searched, filtered and paged by the server (V332). */
export default async function AllCoursesPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const s = (k: string) => (typeof p[k] === "string" ? (p[k] as string) : "");
  const filters: Filters = { q: s("q"), fac: s("fac"), dept: s("dept"), prog: s("prog"), level: s("level"), semester: s("semester"), kind: s("kind"), state: s("state"), session: s("session"), sort: s("sort") || "code", dir: s("dir") || "asc", size: s("size") || "50" };
  const page = Math.max(1, Number(s("page") || "1") || 1);
  const qs = new URLSearchParams();
  for (const [k, v] of Object.entries(filters)) if (v) qs.set(k, v);
  qs.set("page", String(page));
  const [me, list, directory, sessions] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<CourseList>(`/api/v1/catalogue/courses/list?${qs.toString()}`),
    api<Directory>("/api/v1/catalogue/directory"),
    api<{ name: string; state: string }[]>("/api/v1/cohorts/settings").then((r) => (r.ok ? (r.data as unknown as { sessions: { name: string; state: string }[] }).sessions : [])).catch(() => [] as { name: string; state: string }[]),
  ]);
  return (
    <Shell route="t/allcourses" me={me.ok ? me.data : null}>
      {!list.ok ? <ProblemNotice problem={list.problem} /> : (
        <AllCourses list={list.data} directory={directory.ok ? directory.data : null} sessions={sessions.map((x) => x.name)} filters={filters} page={page} generatedBy={me.ok ? me.data.name ?? null : null} />
      )}
    </Shell>
  );
}
