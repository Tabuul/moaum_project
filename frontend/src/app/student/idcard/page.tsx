import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import { loadStudent } from "../load";

export const dynamic = "force-dynamic";
import type { Card } from "@/lib/student-portal";
import { IdCard } from "../Screens5";

/** s/idcard — the card the Library issued */
export default async function Page() {
  const loaded = await loadStudent();
  if (!loaded.student) return <Shell route="s/idcard" me={loaded.me}><ProblemNotice problem={loaded.problem} /></Shell>;
  const d = await api<Card>("/api/v1/me/id-card");
  return (
    <Shell route="s/idcard" me={loaded.me}>
      {d.ok ? <IdCard c={d.data} s={loaded.student} /> : <ProblemNotice problem={d.problem} />}
    </Shell>
  );
}
