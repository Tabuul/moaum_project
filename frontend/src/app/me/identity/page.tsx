import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import type { StaffIdentityState } from "@/lib/identity";
import { StaffIdentity } from "./StaffIdentity";

export const dynamic = "force-dynamic";

/** t/myidentity — V749: "UPDATE STAFF IDENTITY INFORMATION": the member of staff's own passport photograph (checked and enhanced on
 *  the server, accepted before it becomes the card photograph), e-mail address (verified by a code sent to it) and blood group
 *  (confirmed). The person is the one signed in, never a parameter; the dashboard's panel opens here until all three are done. */
export default async function MyIdentityPage() {
  const [me, state] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<StaffIdentityState>("/api/v1/staff/identity"),
  ]);
  return (
    <Shell route="t/myidentity" me={me.ok ? me.data : null}>
      {state.ok ? <StaffIdentity state={state.data} name={me.ok ? me.data.name ?? null : null} /> : <ProblemNotice problem={state.problem} />}
    </Shell>
  );
}
