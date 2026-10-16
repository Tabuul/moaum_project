import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { LevelDesk } from "./LevelDesk";

export const dynamic = "force-dynamic";

/** t/supportlevels — Student Level Management at the ICT Support Desk (V500): find the student within the agent's reach, read the
 *  level and its evidence, and progress or correct it */
export default async function LevelDeskPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const q = typeof p.q === "string" ? p.q.slice(0, 80) : "";
  const student = typeof p.student === "string" && /^[0-9a-f-]{36}$/i.test(p.student) ? p.student : "";
  const me = await api<Me>("/api/v1/iam/me");
  return (
    <Shell route="t/supportlevels" me={me.ok ? me.data : null}>
      <LevelDesk q={q} student={student} />
    </Shell>
  );
}
