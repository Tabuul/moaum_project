import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { JupebApplications } from "../JupebOffice";

export const dynamic = "force-dynamic";

/** /jupeb/applications — every JUPEB candidate of a session, filtered, exported, decided in bulk (V339) */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const me = await api<Me>("/api/v1/iam/me");
  const office = me.ok ? me.data.activeOffice : null;
  const canWrite = office === "jupeb" || office === "super";
  const params = await searchParams;
  const initial: Record<string, string> = {};
  for (const k of ["session", "state", "combination", "fee", "screening", "q"]) if (typeof params[k] === "string") initial[k] = params[k] as string;
  return (
    <Shell route="jupeb/applications" me={me.ok ? me.data : null}>
      <JupebApplications canWrite={canWrite} initial={initial} />
    </Shell>
  );
}
