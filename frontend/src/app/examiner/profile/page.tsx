import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { ExaminerRow } from "@/lib/examiners";
import { Profile } from "./Profile";

export const dynamic = "force-dynamic";

/** x/profile — the examiner's own record: what the University holds, and what they may keep current */
export default async function ExaminerProfilePage() {
  const [me, w] = await Promise.all([api<Me>("/api/v1/iam/me"), api<ExaminerRow>("/api/v1/examiners/me")]);
  return (
    <Shell route="x/profile" me={me.ok ? me.data : null}>
      {w.ok ? <Profile e={w.data} /> : <ProblemNotice problem={w.problem} />}
    </Shell>
  );
}
