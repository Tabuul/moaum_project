import { ExamRoom } from "@/components/cbt/ExamRoom";

export const dynamic = "force-dynamic";

/** s/cbt — the examination room (V322): one attempt, fullscreen, outside the portal's shell. The attempt is the signed-in student's and the
 *  screen must hold its token; the API refuses everything else. */
export default async function Page({ params }: { params: Promise<{ attempt: string }> }) {
  const { attempt } = await params;
  return <ExamRoom attemptId={attempt} />;
}
