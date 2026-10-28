import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { gstQuery, readGstFilters, refreshParam, type GstStudentPage } from "@/lib/gst";
import { GstStudents } from "@/app/gst/GstStudents";

export const dynamic = "force-dynamic";

/** t/gstunpaid — V691: the students with a GST or EPS course registered while the GST fee is unpaid, for the GST office and the Bursary:
 *  what each owes, what the list comes to, Excel, and a reminder to pay */
export default async function GSTUnpaidPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const filters = readGstFilters(p);
  if (!filters.eligibility) filters.eligibility = "UNPAID_REGISTERED";
  const page = typeof p.page === "string" && /^\d+$/.test(p.page) ? Number(p.page) : 0;
  const [me, data] = await Promise.all([api<Me>("/api/v1/iam/me"), api<GstStudentPage>(`/api/v1/gst/GST/students?${gstQuery(filters, { page, size: 50 })}${refreshParam(p)}`)]);
  return (
    <Shell route="t/gstunpaid" me={me.ok ? me.data : null}>
      {data.ok ? <GstStudents data={data.data} filters={filters} base="/gst" path="unpaid" actingOffice={me.ok ? me.data.activeOffice : null} /> : <ProblemNotice problem={data.problem} />}
    </Shell>
  );
}
