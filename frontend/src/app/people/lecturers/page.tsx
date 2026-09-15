import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { Lecturers, type StaffRow } from "./Lecturers";

export const dynamic = "force-dynamic";

/** t/lecturers — bulk-onboard teaching staff and view the staff on record (V137). */
export default async function LecturersPage() {
  const [me, list] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<StaffRow[]>("/api/v1/iam/lecturers"),
  ]);
  return (
    <Shell route="t/lecturers" me={me.ok ? me.data : null}>
      <Lecturers actingOffice={me.ok ? me.data.activeOffice : null} staff={list.ok ? list.data : []} />
    </Shell>
  );
}
