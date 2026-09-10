import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Recruitment, type Vacancy, type Applicants } from "./Recruitment";

export const dynamic = "force-dynamic";

/** t/recruit — recruitment: vacancies and the applications scored against them. */
export default async function RecruitmentPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const vacancyId = typeof p.vacancy === "string" ? p.vacancy : null;
  const [me, list, applicants] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<{ rows: Vacancy[] }>("/api/v1/hr/vacancies"),
    vacancyId ? api<Applicants>(`/api/v1/hr/vacancies/${vacancyId}/applicants`) : Promise.resolve(null),
  ]);
  return (
    <Shell route="t/recruit" me={me.ok ? me.data : null}>
      {list.ok ? (
        <Recruitment
          rows={list.data.rows}
          applicants={applicants && applicants.ok ? applicants.data : null}
          actingOffice={me.ok ? me.data.activeOffice : null}
        />
      ) : <ProblemNotice problem={list.problem} />}
    </Shell>
  );
}
