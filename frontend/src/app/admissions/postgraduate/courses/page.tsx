import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { CoursesDesk } from "./CoursesDesk";
import { PgClasses } from "./PgClasses";

export const dynamic = "force-dynamic";

const EDITORS = ["hod", "academic", "pgschool", "pgsecretary", "super"];

/** PG course catalogue (V211): the department / School defines the courses each programme carries. */
export default async function Page() {
  const me = await api<Me>("/api/v1/iam/me");
  const office = me.ok ? me.data.activeOffice : null;
  return (
    <Shell route="t/pgcourses" me={me.ok ? me.data : null}>
      <PgClasses mayOpen={["academic", "pgschool", "pgsecretary", "super"].includes(office ?? "")} />
      <CoursesDesk mayEdit={EDITORS.includes(office ?? "")} />
    </Shell>
  );
}
