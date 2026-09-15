import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import { loadStudent } from "../load";

export const dynamic = "force-dynamic";
import type { Results } from "@/lib/student-portal";
import { Broadsheet } from "../Screens4";

/** s/broadsheet — the student's own results laid out as a broadsheet, semester by semester */
export default async function Page() {
  const loaded = await loadStudent();
  if (!loaded.student) return <Shell route="s/broadsheet" me={loaded.me}><ProblemNotice problem={loaded.problem} /></Shell>;
  const r = await api<Results>("/api/v1/me/results");
  return (
    <Shell route="s/broadsheet" me={loaded.me}>
      {r.ok ? <Broadsheet r={r.data} /> : <ProblemNotice problem={r.problem} />}
    </Shell>
  );
}
