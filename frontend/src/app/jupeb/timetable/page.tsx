import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { JupebTimetable } from "./JupebTimetable";

export const dynamic = "force-dynamic";

/** /jupeb/timetable — the week's lectures of each JUPEB subject, by class and semester (V347); the API decides who reads and who writes */
export default async function Page() {
  const me = await api<Me>("/api/v1/iam/me");
  const office = me.ok ? me.data.activeOffice : null;
  const canWrite = office === "jupeb" || office === "super";
  return (
    <Shell route="jupeb/timetable" me={me.ok ? me.data : null}>
      <JupebTimetable canWrite={canWrite} />
    </Shell>
  );
}
