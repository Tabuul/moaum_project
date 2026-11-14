import { api } from "@/lib/api";
import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { MySiwes } from "@/lib/siwes";
import { loadStudent } from "../load";
import { Siwes } from "./Siwes";

export const dynamic = "force-dynamic";

/** s/siwes — V752: SIWES registration at 300 Level, Second Semester (the University's master prompt of 12 November 2026). The student
 *  sees whether SIWES is theirs this session and why not when it is not; the SIWES course, the training dates and the deadline; pays the
 *  SIWES registration fee through the gateways every fee uses; then registers the SIWES course — the only course of that semester — and
 *  prints it. The gateway returns the payer here with ?paid=<reference>: verified with the gateway at once, before the page is read. */
export default async function StudentSiwesPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const q = await searchParams;
  const paid = typeof q.paid === "string" && /^[A-Z0-9-]{6,60}$/i.test(q.paid) ? q.paid.toUpperCase() : null;
  const session = typeof q.session === "string" && /^\d{4}\/\d{4}$/.test(q.session) ? q.session : null;
  const [loaded] = await Promise.all([
    loadStudent(),
    paid ? api("/api/v1/payments/verify", { method: "POST", body: { reference: paid }, reason: `Verify payment ${paid}` }) : null,
  ]);
  const data = await api<MySiwes>(`/api/v1/me/siwes${session ? `?session=${encodeURIComponent(session)}` : ""}`);
  return (
    <Shell route="s/siwes" me={loaded.me}>
      {data.ok && loaded.student ? <Siwes d={data.data} paid={paid} name={loaded.student.name} number={loaded.student.matricNo ?? loaded.student.admissionNo ?? ""} />
        : !data.ok ? <ProblemNotice problem={data.problem} /> : "problem" in loaded ? <ProblemNotice problem={loaded.problem} /> : null}
    </Shell>
  );
}
