import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ApplicantPasswords, type ResetRow } from "./ApplicantPasswords";

export const dynamic = "force-dynamic";

/** t/applicantpw — Post-UTME applicant passwords reset (V687): the Director of ICT, the Academic Office and ICT Support; the API decides */
export default async function Page() {
  const [me, history] = await Promise.all([api<Me>("/api/v1/iam/me"), api<ResetRow[]>("/api/v1/applicant-passwords/history?limit=200")]);
  return (
    <Shell route="t/applicantpw" me={me.ok ? me.data : null}>
      <ApplicantPasswords office={me.ok ? me.data.activeOffice ?? null : null} history={history.ok ? history.data : []} problem={history.ok ? null : history.problem} />
    </Shell>
  );
}
