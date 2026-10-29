import { api } from "@/lib/api";
import { loadScope } from "@/lib/scope-data";
import { Shell, type Me } from "@/components/proto/Shell";
import { HeldFeesDesk } from "./HeldFees";

export const dynamic = "force-dynamic";

/** f/heldfees — V702: the students held a level behind after a change of department, their fee held and without the hold */
export default async function HeldFeesPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const params = await searchParams;
  const { scope, sessions } = await loadScope(params);
  const me = await api<Me>("/api/v1/iam/me");
  return (
    <Shell route="f/heldfees" me={me.ok ? me.data : null}>
      <HeldFeesDesk session={scope.session} sessions={sessions} />
    </Shell>
  );
}
