import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { Rubric } from "@/lib/examiners";
import { Rubrics } from "./Rubrics";

export const dynamic = "force-dynamic";

/** t/extrubrics — the assessment forms: criteria, sections and maxima the University configures */
export default async function RubricsPage() {
  const [me, list] = await Promise.all([api<Me>("/api/v1/iam/me"), api<Rubric[]>("/api/v1/examiners/rubrics")]);
  const office = me.ok ? me.data.activeOffice : null;
  return (
    <Shell route="t/extassessments" me={me.ok ? me.data : null}>
      {list.ok ? <Rubrics rubrics={list.data} mayEdit={["academic", "dregistrar", "pgschool", "admin", "super"].includes(office ?? "")} /> : <ProblemNotice problem={list.problem} />}
    </Shell>
  );
}
