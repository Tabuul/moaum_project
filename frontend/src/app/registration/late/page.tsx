import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { LateRow } from "@/lib/late-registration";
import { LateRegistration } from "./LateRegistration";

export const dynamic = "force-dynamic";

/** t/latereg — Late registration (V516): the Registry registers a student after the window closed, on the student's behalf, with a
 *  reason; the window and add and drop are set aside, every other rule holds */
export default async function LateRegistrationPage() {
  const [me, list] = await Promise.all([api<Me>("/api/v1/iam/me"), api<{ session: string; rows: LateRow[] }>("/api/v1/registration/late")]);
  const office = me.ok ? me.data.activeOffice ?? "" : "";
  return (
    <Shell route="t/latereg" me={me.ok ? me.data : null} sub={list.ok ? list.data.session : undefined}>
      {!list.ok ? <ProblemNotice problem={list.problem} />
        : <LateRegistration recent={list.data.rows} session={list.data.session} mayRegister={["registrar", "dregistrar", "super"].includes(office)} />}
    </Shell>
  );
}
