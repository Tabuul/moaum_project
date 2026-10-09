import { ExamRoom } from "@/components/cbt/ExamRoom";

export const dynamic = "force-dynamic";

/** V371: the examination room on the office's own paper — the paper as a candidate sees it, outside the portal's shell, for the office
 *  that manages the examination (the API refuses everyone else). No attempt is made and nothing is saved, reported or submitted. */
export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <ExamRoom attemptId="preview" previewExamId={id} />;
}
