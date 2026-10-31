import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { filtersFrom, filtersQuery, type SearchAnswer } from "@/lib/pg-records";
import { PgRecords } from "./PgRecords";

export const dynamic = "force-dynamic";

/** /admissions/postgraduate/records — V715: postgraduate applicants and students found and opened for correction; the search in the address */
export default async function PgRecordsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const sp = await searchParams;
  const filters = filtersFrom(sp);
  const [me, answer] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<SearchAnswer>(`/api/v1/pg/records/search?${filtersQuery(filters)}`),
  ]);
  return (
    <Shell route="t/pgrecords" me={me.ok ? me.data : null}>
      {answer.ok ? <PgRecords initial={answer.data} filters={filters} actingOffice={me.ok ? me.data.activeOffice ?? null : null} /> : <ProblemNotice problem={answer.problem} />}
    </Shell>
  );
}
