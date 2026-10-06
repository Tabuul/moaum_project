import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { JupebAttendance } from "./JupebAttendance";

export const dynamic = "force-dynamic";

/** /jupeb/attendance — JUPEB registers, reports, instructors and the minimum (V342); what each person sees is the API's to decide */
export default async function Page() {
  const me = await api<Me>("/api/v1/iam/me");
  return (
    <Shell route="jupeb/attendance" me={me.ok ? me.data : null}>
      <JupebAttendance />
    </Shell>
  );
}
