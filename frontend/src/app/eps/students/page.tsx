import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { gstQuery, readGstFilters, type GstStudentPage } from "@/lib/gst";
import { GstStudents } from "@/app/gst/GstStudents";

export const dynamic = "force-dynamic";

/** t/epsstudents — the EPS office's students (V314): the rows behind a figure, paged, searched and exported */
export default async function EPSStudentsPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const filters = readGstFilters(p);
  const page = typeof p.page === "string" && /^\d+$/.test(p.page) ? Number(p.page) : 0;
  const [me, data] = await Promise.all([api<Me>("/api/v1/iam/me"), api<GstStudentPage>(`/api/v1/gst/EPS/students?${gstQuery(filters, { page, size: 50 })}`)]);
  return (
    <Shell route="t/epsstudents" me={me.ok ? me.data : null}>
      {data.ok ? <GstStudents data={data.data} filters={filters} base="/eps" /> : <ProblemNotice problem={data.problem} />}
    </Shell>
  );
}
