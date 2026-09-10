import { api } from "@/lib/api";
import { ProblemNotice } from "@/components/ProblemNotice";
import { TransferLetter, type LetterApp } from "./TransferLetter";

export const dynamic = "force-dynamic";

interface MyTransfer {
  student: { name: string; matric_no: string | null; programme: string };
  applications: LetterApp[];
}

/** The student's own approval letter for an approved / effected transfer, printable. */
export default async function TransferLetterPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const data = await api<MyTransfer>("/api/v1/me/transfer");
  if (!data.ok) return <div style={{ padding: 24 }}><ProblemNotice problem={data.problem} /></div>;
  const app = data.data.applications.find((a) => a.id === id) ?? null;
  if (!app || !["APPROVED", "EFFECTED"].includes(app.state)) {
    return <div style={{ padding: 24 }}>No approval letter is available for this application yet.</div>;
  }
  return <TransferLetter student={data.data.student} app={app} />;
}
