import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import type { StaffChange } from "@/lib/staff-removal";
import { Lecturers, type StaffRow } from "./Lecturers";

export const dynamic = "force-dynamic";

/** t/lecturers — bulk-onboard teaching staff and view the staff on record (V137); delete or deactivate, and restore (V656). */
export default async function LecturersPage() {
  const [me, list, removed] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<StaffRow[]>("/api/v1/iam/lecturers"),
    api<StaffChange[]>("/api/v1/iam/staff/removed?category=ACADEMIC"),
  ]);
  return (
    <Shell route="t/lecturers" me={me.ok ? me.data : null}>
      <Lecturers actingOffice={me.ok ? me.data.activeOffice : null} staff={list.ok ? list.data : []} removed={removed.ok ? removed.data : []} />
    </Shell>
  );
}
