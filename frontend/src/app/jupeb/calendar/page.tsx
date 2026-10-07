import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { JupebCalendar } from "./JupebCalendar";

export const dynamic = "force-dynamic";

/** /jupeb/calendar — the JUPEB session calendar, the Board's and the University's (V354); the API decides who reads and who writes */
export default async function Page() {
  const me = await api<Me>("/api/v1/iam/me");
  const office = me.ok ? me.data.activeOffice : null;
  const canWrite = office === "jupeb" || office === "super";
  return (
    <Shell route="jupeb/calendar" me={me.ok ? me.data : null}>
      <JupebCalendar canWrite={canWrite} />
    </Shell>
  );
}
