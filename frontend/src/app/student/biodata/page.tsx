import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import type { StudentRecord } from "@/lib/student";
import { loadStudent } from "../load";
import { Biodata } from "@/app/students/[id]/Biodata";

export const dynamic = "force-dynamic";

/** s/biodata — the student's own record, in full: read from JAMB, self-service, or on evidence. */
export default async function Page() {
  const loaded = await loadStudent();
  if (!loaded.student) {
    return <Shell route="s/biodata" me={loaded.me}><ProblemNotice problem={loaded.problem} /></Shell>;
  }
  const rec = await api<StudentRecord>("/api/v1/me/biodata");
  return (
    <Shell route="s/biodata" me={loaded.me}>
      {rec.ok ? <Biodata record={rec.data} may base="/api/bff/api/v1/me" /> : <ProblemNotice problem={rec.problem} />}
    </Shell>
  );
}
