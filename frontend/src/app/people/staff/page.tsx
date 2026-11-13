import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import type { StaffChange } from "@/lib/staff-removal";
import { NonAcademic, type NonAcademicRow, type OfficeRow, type Unit } from "./NonAcademic";

export const dynamic = "force-dynamic";

/** t/staffupload — load the nominal roll of non-academic staff into their units, and see who is on record (V253); add one,
 *  delete or deactivate, and restore (V656); V754: the unit each office belongs to */
export default async function NonAcademicStaffPage() {
  const [me, list, units, removed, offices] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<NonAcademicRow[]>("/api/v1/iam/staff"),
    api<Unit[]>("/api/v1/iam/units"),
    api<StaffChange[]>("/api/v1/iam/staff/removed?category=NON_ACADEMIC"),
    api<OfficeRow[]>("/api/v1/iam/offices"),
  ]);
  return (
    <Shell route="t/staffupload" me={me.ok ? me.data : null}>
      <NonAcademic actingOffice={me.ok ? me.data.activeOffice : null} staff={list.ok ? list.data : []} units={units.ok ? units.data : []}
        removed={removed.ok ? removed.data : []} offices={offices.ok ? offices.data : []} />
    </Shell>
  );
}
