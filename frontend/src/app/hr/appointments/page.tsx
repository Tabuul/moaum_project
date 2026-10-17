import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { AppointmentsOverview } from "@/lib/appointments";
import { Appointments } from "./Appointments";

export const dynamic = "force-dynamic";

/** t/appoint — New appointments (V510): the employment record made from a form or an Excel upload, checked first, and the salary
 *  grades it names */
export default async function AppointmentsPage() {
  const [me, o] = await Promise.all([api<Me>("/api/v1/iam/me"), api<AppointmentsOverview>("/api/v1/hr/appointments")]);
  const office = me.ok ? me.data.activeOffice ?? "" : "";
  return (
    <Shell route="t/appoint" me={me.ok ? me.data : null}>
      {!o.ok ? <ProblemNotice problem={o.problem} />
        : <Appointments o={o.data} mayAppoint={["hrm", "super"].includes(office)} maySetGrades={["hrm", "bursar", "super"].includes(office)} />}
    </Shell>
  );
}
