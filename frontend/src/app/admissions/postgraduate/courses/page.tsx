import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { LinkBtn, Note } from "@/components/proto/ui";
import { CoursesDesk } from "./CoursesDesk";
import { PgClasses } from "./PgClasses";

export const dynamic = "force-dynamic";

const EDITORS = ["hod", "academic", "pgschool", "pgsecretary", "super"];

/** PG course catalogue (V211): the department / School defines the courses each programme carries. V471: the lists read the
 *  programmes' structures on the University's one course pool — what Programme Structure shows and registration reads; a course
 *  added or uploaded here is bound there. */
export default async function Page() {
  const me = await api<Me>("/api/v1/iam/me");
  const office = me.ok ? me.data.activeOffice : null;
  return (
    <Shell route="t/pgcourses" me={me.ok ? me.data : null}>
      <Note kind="info" title="One course list for the University" action={<><LinkBtn href="/catalogue/structure">Programme structure</LinkBtn><LinkBtn href="/catalogue/structure/checks">Structure checks</LinkBtn></>}>
        The courses below are the postgraduate programmes&rsquo; structures on the University&rsquo;s course pool. A course added or uploaded here is bound into its programme there; bind, remove, prerequisites and levels are worked on Programme Structure.
      </Note>
      <PgClasses mayOpen={["academic", "pgschool", "pgsecretary", "super"].includes(office ?? "")} />
      <CoursesDesk mayEdit={EDITORS.includes(office ?? "")} />
    </Shell>
  );
}
