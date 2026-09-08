import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import type { Graduation } from "@/lib/student-portal";
import { loadStudent } from "../load";
import { GraduationScreen } from "../Screens6";

export const dynamic = "force-dynamic";

/** s/graduation — the loop closed at the student's end: the audit, Senate's word, clearance, the certificate */
export default async function Page() {
  const loaded = await loadStudent();
  const g = loaded.student ? await api<Graduation>("/api/v1/me/graduation") : null;
  return (
    <Shell route="s/graduation" me={loaded.me}>
      {loaded.student && g && g.ok ? <GraduationScreen g={g.data} /> : <ProblemNotice problem={g && !g.ok ? g.problem : loaded.student ? { status: 500, title: "Unreadable" } : loaded.problem} />}
    </Shell>
  );
}
