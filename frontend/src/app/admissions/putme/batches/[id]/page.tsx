import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { intakeSession, type SessionRow } from "@/lib/sessions";
import type { Batch, Candidate, PutmeExam } from "@/lib/putme";
import { BatchPage } from "./Batch";

export const dynamic = "force-dynamic";

export interface BatchFull extends Batch { candidates: Candidate[]; byProgramme: { programme: string; faculty: string | null; n: number }[]; byFaculty: { faculty: string | null; n: number }[]; exam: PutmeExam | null }

/** t/putme-cbt › batch — one batch: its place, its candidates in seat order with attendance, the sheet for the hall, and the batch postponed or cancelled */
export default async function PutmeBatchPage({ params, searchParams }: { params: Promise<{ id: string }>; searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const { id } = await params;
  const p = await searchParams;
  const [me, sessions] = await Promise.all([api<Me>("/api/v1/iam/me"), api<SessionRow[]>("/api/v1/ref/sessions")]);
  const list = sessions.ok ? sessions.data : [];
  const session = typeof p.session === "string" && /^\d{4}\/\d{4}$/.test(p.session) ? p.session : intakeSession(list);
  const [view, batches] = await Promise.all([api<BatchFull>(`/api/v1/admissions/sessions/${session}/putme/batches/${id}`), api<Batch[]>(`/api/v1/admissions/sessions/${session}/putme/batches`)]);
  return (
    <Shell route="t/putme-cbt" me={me.ok ? me.data : null}>
      {view.ok ? <BatchPage b={view.data} session={session} batches={batches.ok ? batches.data : []} office={me.ok ? me.data.activeOffice ?? null : null} /> : <ProblemNotice problem={view.problem} />}
    </Shell>
  );
}
