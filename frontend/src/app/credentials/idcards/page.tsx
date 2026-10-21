import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { IdCards, type CardDesk, type StaffDesk } from "./IdCards";
import { IdCardDesk } from "./IdCardDesk";

export const dynamic = "force-dynamic";

/** t/idcards — the Security Unit's student identity card desk (V605): search, the student, eligibility, print, issue, replace, history — above the card register and the staff cards */
export default async function IdCardsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const q = typeof params.q === "string" ? params.q : "";
  const student = typeof params.student === "string" ? params.student : null;
  const [me, desk, staff] = await Promise.all([api<Me>("/api/v1/iam/me"), api<CardDesk>(`/api/v1/credentials/identity-cards${q ? `?q=${encodeURIComponent(q)}` : ""}`),
    api<StaffDesk>(`/api/v1/credentials/identity-cards/staff${q ? `?q=${encodeURIComponent(q)}` : ""}`)]);
  return (
    <Shell route="t/idcards" me={me.ok ? me.data : null}>
      <IdCardDesk actingOffice={me.ok ? me.data.activeOffice : null} initialStudent={student} />
      {desk.ok ? <IdCards desk={desk.data} staff={staff.ok ? staff.data : null} q={q} actingOffice={me.ok ? me.data.activeOffice : null} /> : <ProblemNotice problem={desk.problem} />}
    </Shell>
  );
}
