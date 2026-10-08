import { ExamRoom } from "@/components/cbt/ExamRoom";

export const dynamic = "force-dynamic";

/** the JUPEB student's examination room (V365): the same room as the University's, behind the JUPEB door; the API refuses everything but the candidate's own attempt */
export default async function Page({ params }: { params: Promise<{ attempt: string }> }) {
  const { attempt } = await params;
  return <ExamRoom attemptId={attempt} apiBase="/api/bff/api/v1/jupeb/me/cbt" listHref="/jupeb/portal?tab=cbt" listLabel="your CBT examinations" />;
}
