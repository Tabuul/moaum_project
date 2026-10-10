import { ExamRoom } from "@/components/cbt/ExamRoom";

export const dynamic = "force-dynamic";

/** /post-utme/cbt/room/[attempt] — the Post-UTME examination room (V385): the same room every candidate sits in, behind the candidate's own door.
 *  The attempt is the verified candidate's and the screen must hold its token; the API refuses everything else and gives no score. */
export default async function Page({ params }: { params: Promise<{ attempt: string }> }) {
  const { attempt } = await params;
  return <ExamRoom attemptId={attempt} apiBase="/api/bff/api/v1/putme/cbt" listHref="/post-utme/cbt" listLabel="Post-UTME CBT" />;
}
