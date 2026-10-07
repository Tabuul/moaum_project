import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { JupebAnnouncements } from "./JupebAnnouncements";

export const dynamic = "force-dynamic";

/** /jupeb/announcements — the JUPEB Office's notices to a session's candidates and students (V349); the API decides who reads and who publishes */
export default async function Page() {
  const me = await api<Me>("/api/v1/iam/me");
  const office = me.ok ? me.data.activeOffice : null;
  const canWrite = office === "jupeb" || office === "super";
  return (
    <Shell route="jupeb/announcements" me={me.ok ? me.data : null}>
      <JupebAnnouncements canWrite={canWrite} />
    </Shell>
  );
}
