import { api } from "@/lib/api";
import type { TranscriptQueue } from "@/lib/credentials";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Transcripts } from "./Transcripts";

export const dynamic = "force-dynamic";

export default async function TranscriptsPage() {
  const [me, queue] = await Promise.all([api<Me>("/api/v1/iam/me"), api<TranscriptQueue>("/api/v1/credentials/transcript-requests")]);
  return (
    <Shell route="t/transcripts" me={me.ok ? me.data : null}>
      {queue.ok ? <Transcripts queue={queue.data} actingOffice={me.ok ? me.data.activeOffice : null} /> : <ProblemNotice problem={queue.problem} />}
    </Shell>
  );
}
