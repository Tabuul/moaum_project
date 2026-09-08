import { api } from "@/lib/api";
import type { FacultyList } from "@/lib/matriculation";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { FacultyListScreen } from "./FacultyListScreen";

export const dynamic = "force-dynamic";

const SESSION_PATTERN = /^\d{4}\/\d{4}$/;

export default async function FacultyListPage({ params, searchParams }: { params: Promise<{ code: string }>; searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const { code } = await params;
  const q = await searchParams;
  const requested = typeof q.session === "string" ? q.session : "2026/2027";
  const session = SESSION_PATTERN.test(requested) ? requested : "2026/2027";
  const [me, list] = await Promise.all([api<Me>("/api/v1/iam/me"), api<FacultyList>(`/api/v1/matriculation/sessions/${session}/faculties/${encodeURIComponent(code)}`)]);
  return (
    <Shell route="t/matriculation" me={me.ok ? me.data : null}>
      {list.ok ? <FacultyListScreen list={list.data} actingOffice={me.ok ? me.data.activeOffice : null} /> : <ProblemNotice problem={list.problem} />}
    </Shell>
  );
}
