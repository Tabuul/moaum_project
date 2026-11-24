import { api } from "@/lib/api";
import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { sessionRows } from "@/lib/sessions-server";
import { lastSessions, type MySummer } from "@/lib/summer";
import { loadStudent } from "../load";
import { Summer } from "./Summer";

export const dynamic = "force-dynamic";

/** s/summer — V735, V779: the Summer Semester of a final-year or spillover student: whether they may take it and why, the courses of
 *  their programme and their record to search and select, the itemised fees the Bursary published, one payment for what is owed, the
 *  Academic Office's verification of each selection, and the registration the payment makes (printable).
 *  The gateway returns the payer here with ?paid=<reference>: verified with the gateway at once, before the page is read. */
export default async function StudentSummerPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const q = await searchParams;
  const paid = typeof q.paid === "string" && /^[A-Z0-9-]{6,60}$/i.test(q.paid) ? q.paid.toUpperCase() : null;
  const session = typeof q.session === "string" && /^\d{4}\/\d{4}$/.test(q.session) ? q.session : null;
  const [loaded] = await Promise.all([
    loadStudent(),
    paid ? api("/api/v1/payments/verify", { method: "POST", body: { reference: paid }, reason: `Verify payment ${paid}` }) : null,
  ]);
  const data = await api<MySummer>(`/api/v1/me/summer${session ? `?session=${encodeURIComponent(session)}` : ""}`);
  // "Where did you owe it?": the University's own sessions, the last six up to the Summer's; none when the calendar cannot be read
  const sessions = data.ok && data.data.session ? lastSessions((await sessionRows()).map((s) => s.name), data.data.session) : [];
  return (
    <Shell route="s/summer" me={loaded.me}>
      {data.ok && loaded.student ? <Summer d={data.data} paid={paid} sessions={sessions} name={loaded.student.name} number={loaded.student.matricNo ?? loaded.student.admissionNo ?? ""} />
        : !data.ok ? <ProblemNotice problem={data.problem} /> : "problem" in loaded ? <ProblemNotice problem={loaded.problem} /> : null}
    </Shell>
  );
}
