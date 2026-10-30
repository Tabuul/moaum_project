import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { PgApplicantPasswords, type PgResetRow } from "./PgApplicantPasswords";

export const dynamic = "force-dynamic";

/** t/pgapplicantpw — postgraduate applicant passwords reset to the application number (V706): the Dean and the Secretary of the School of
 *  Postgraduate Studies, the Director of ICT and ICT Support; the API decides. ?q= searches on opening (the School's dashboard). */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const q = typeof p.q === "string" ? p.q.slice(0, 160) : "";
  const [me, history] = await Promise.all([api<Me>("/api/v1/iam/me"), api<PgResetRow[]>("/api/v1/pg/applicant-passwords/history?limit=200")]);
  return (
    <Shell route="t/pgapplicantpw" me={me.ok ? me.data : null}>
      <PgApplicantPasswords office={me.ok ? me.data.activeOffice ?? null : null} history={history.ok ? history.data : []}
        problem={history.ok ? null : history.problem} initialQuery={q} />
    </Shell>
  );
}
