import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import type { StudentHealth } from "@/lib/health";
import { loadStudent } from "../load";
import { Health } from "./Health";

export const dynamic = "force-dynamic";

/** s/health — only the clinic sees your medical notes */
export default async function Page() {
  const loaded = await loadStudent();
  const h = loaded.student ? await api<StudentHealth>("/api/v1/me/health") : null;
  return (
    <Shell route="s/health" me={loaded.me}>
      {loaded.student && h && h.ok ? <Health h={h.data} /> : <ProblemNotice problem={h && !h.ok ? h.problem : loaded.student ? { status: 500, title: "Unreadable" } : loaded.problem} />}
    </Shell>
  );
}
