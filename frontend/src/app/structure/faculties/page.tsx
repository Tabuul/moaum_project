import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { Faculties, type Faculty } from "./Faculties";

export const dynamic = "force-dynamic";

/** t/facultyupload — create or upload faculties (V091). */
export default async function FacultiesPage() {
  const [me, list] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<Faculty[]>("/api/v1/catalogue/faculties"),
  ]);
  return (
    <Shell route="t/facultyupload" me={me.ok ? me.data : null}>
      {list.ok ? <Faculties faculties={list.data} actingOffice={me.ok ? me.data.activeOffice : null} /> : <ProblemNotice problem={list.problem} />}
    </Shell>
  );
}
