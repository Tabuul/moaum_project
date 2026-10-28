import { redirect } from "next/navigation";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import { ApplicantPassword, type PasswordState } from "./ApplicantPassword";

export const dynamic = "force-dynamic";

/** a/mypassword — the applicant's own password (V687): required after a temporary one from the University, open at any time */
export default async function Page() {
  const [who, state] = await Promise.all([api<Me>("/api/v1/iam/me"), api<PasswordState>("/api/v1/applicant/me/password")]);
  if (who.ok && who.data.activeOffice !== "applicant") redirect("/");
  if (!state.ok && state.problem.status === 401) redirect("/login");
  /* a JUPEB or postgraduate candidate has no Post-UTME account here: their own portal */
  if (!state.ok && state.problem.status === 404) redirect("/");
  const me: Me | null = state.ok
    ? {
        actorId: who.ok ? who.data.actorId : "", activeOffice: "applicant", offices: ["applicant"], name: state.data.name, staffNumber: state.data.applicationNo,
        sessionId: who.ok ? who.data.sessionId ?? null : null, waiting: {}, flags: [], menu: null, unit: null,
      }
    : who.ok ? who.data : null;
  return (
    <Shell route="a/mypassword" me={me}>
      {state.ok ? <ApplicantPassword state={state.data} /> : <ProblemNotice problem={state.problem} />}
    </Shell>
  );
}
