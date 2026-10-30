import { redirect } from "next/navigation";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import { PgPassword, type PgPasswordState } from "./PgPassword";

export const dynamic = "force-dynamic";

/** pg/password — the postgraduate applicant's own password (V706): required after the University reset it to the application number,
 *  open at any time */
export default async function Page() {
  const state = await api<PgPasswordState>("/api/v1/pg/me/password");
  if (!state.ok && state.problem.status === 401) redirect("/login?next=/pg/portal/password");
  /* an undergraduate or JUPEB applicant has no postgraduate account: their own portal */
  if (!state.ok && (state.problem.status === 404 || state.problem.status === 403)) redirect("/");
  const me: Me | null = state.ok
    ? { actorId: "", activeOffice: "pgapplicant", offices: ["pgapplicant"], name: state.data.name, staffNumber: state.data.applicationNo, sessionId: null, unit: null, waiting: {} }
    : null;
  return (
    <Shell route="pg/password" me={me}>
      {state.ok ? <PgPassword state={state.data} /> : <ProblemNotice problem={state.problem} />}
    </Shell>
  );
}
