import { redirect } from "next/navigation";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import type { IutMe } from "@/lib/transfer-application";
import { TransferPassword } from "./TransferPassword";

export const dynamic = "force-dynamic";

/** iut/password — V766: the transfer applicant's own password, which also opens the student door once they are admitted, at the first
 *  sign-in there (D18); from then on the student portal keeps its own (portalOpened), and the page says so */
export default async function Page() {
  const state = await api<IutMe>("/api/v1/transfer-applications/me");
  if (!state.ok && state.problem.status === 401) redirect("/login?next=/transfer/portal/password");
  /* another applicant's account (Post-UTME, postgraduate, JUPEB) has no transfer application: their own portal */
  if (!state.ok && (state.problem.status === 404 || state.problem.status === 403)) redirect("/");
  const me: Me | null = state.ok
    ? { actorId: "", activeOffice: "iutapplicant", offices: ["iutapplicant"], menu: "iutapplicant", name: `${state.data.applicant?.surname ?? ""}, ${state.data.applicant?.otherNames ?? ""}`,
        staffNumber: state.data.applicationNo, sessionId: null, unit: null, waiting: {} }
    : null;
  return (
    <Shell route="iut/password" me={me}>
      {state.ok ? <TransferPassword applicationNo={state.data.applicationNo} jambRegNo={state.data.applicant?.jambRegNo ?? null} admitted={state.data.state === "ADMITTED"}
        portalOpened={state.data.student?.portalOpened === true} />
        : <ProblemNotice problem={state.problem} />}
    </Shell>
  );
}
