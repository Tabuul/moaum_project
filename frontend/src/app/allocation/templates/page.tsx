import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { BulkUpload, type ImportRecord } from "../../allocate/BulkUpload";

export const dynamic = "force-dynamic";

/** t/allocationtemplates — V478: course allocation by a department's template, for the offices that allocate from one without
 *  the allocation desks: the School of Postgraduate Studies (a department's postgraduate classes) and any office that prefers
 *  the template's page. The department, kind of programme, session and semester are chosen first; the template is built from
 *  the register; the completed file is checked against the template and the register before anything is written. */
export default async function AllocationTemplatesPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const [me, imports] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<ImportRecord[]>("/api/v1/allocation/imports?limit=50").then((r) => (r.ok ? r.data : [])).catch(() => [] as ImportRecord[]),
  ]);
  const office = me.ok ? me.data.activeOffice : null;
  const pg = office === "pgschool" || office === "pgsecretary";
  return (
    <Shell route="t/allocationtemplates" me={me.ok ? me.data : null}>
      <BulkUpload dept={typeof p.dept === "string" ? p.dept : ""} deptName="" session={typeof p.session === "string" ? p.session : ""} semester={Number(p.sem) || 0}
        imports={imports} canImport templateOnly={pg} ticketInitial={typeof p.ticket === "string" ? p.ticket : ""} />
    </Shell>
  );
}
