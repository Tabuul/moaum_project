import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { Lecturers } from "./Lecturers";

export const dynamic = "force-dynamic";

/** t/lecturers — bulk-onboard lecturers: person + sign-in + lecturer office scoped to department (V135). */
export default async function LecturersPage() {
  const me = await api<Me>("/api/v1/iam/me");
  return (
    <Shell route="t/lecturers" me={me.ok ? me.data : null}>
      <Lecturers actingOffice={me.ok ? me.data.activeOffice : null} />
    </Shell>
  );
}
