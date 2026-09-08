import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import { loadStudent } from "../load";

export const dynamic = "force-dynamic";
import type { Transcripts } from "@/lib/student-portal";
import { Transcript } from "../Screens5";

/** s/transcript — the request, the fee, the Registry's stages */
export default async function Page() {
  const loaded = await loadStudent();
  if (!loaded.student) return <Shell route="s/transcript" me={loaded.me}><ProblemNotice problem={loaded.problem} /></Shell>;
  const d = await api<Transcripts>("/api/v1/me/transcripts");
  return (
    <Shell route="s/transcript" me={loaded.me}>
      {d.ok ? <Transcript t={d.data} s={loaded.student} /> : <ProblemNotice problem={d.problem} />}
    </Shell>
  );
}
