"use client";

/** t/deptstaff — the HOD's own department's academic staff: names and ranks, no payroll. Read-only. */
import { Note, Panel, PBody, Pil, Tiles } from "@/components/proto/ui";
import { DTable } from "@/components/proto/DTable";

interface Staff { name: string; pno: string | null; present_rank: string | null; sex: string | null; employment: string | null; teaches: boolean }
export interface DeptStaff { resolved: boolean; dept?: string; deptName?: string; staff?: Staff[] }

export function StaffList({ data }: { data: DeptStaff }) {
  if (!data.resolved) {
    return (
      <Note kind="bad" title="Your Head-of-Department office is not tied to a department yet">
        The list is scoped to your department, and the portal cannot tell which one this office holds. Ask the Registry to
        set the department on your Head-of-Department assignment.
      </Note>
    );
  }
  const staff = data.staff ?? [];
  const teaching = staff.filter((s) => s.teaches).length;
  return (
    <>
      <Tiles items={[
        ["Staff on the establishment", String(staff.length), null, data.deptName ?? ""],
        ["Hold a teaching office", String(teaching), null, "Can be allocated courses"],
        ["Professors", String(staff.filter((s) => (s.present_rank ?? "").toUpperCase().includes("PROFESSOR")).length), null, "By present rank"],
      ]} />
      <Panel title={`Academic staff · ${data.deptName}`} right={`${staff.length} on record`}>
        {staff.length ? (
          <DTable
            cols={["Name", "Rank", "No.|mid", "Sex|mid", "Teaching|mid", "Status|mid"]}
            rows={staff.map((s) => [
              <strong key="n">{s.name}</strong>,
              <span className="sub2" key="r">{s.present_rank ?? "—"}</span>,
              <span className="tnum sub2" key="p">{s.pno ?? "—"}</span>,
              <span className="sub2" key="x">{s.sex === "F" ? "Female" : s.sex === "M" ? "Male" : "—"}</span>,
              s.teaches ? <Pil kind="ok" key="t">Teaching</Pil> : <Pil kind="grey" key="t">—</Pil>,
              <Pil kind={s.employment === "ACTIVE" ? "ok" : "grey"} key="e">{s.employment ? s.employment.charAt(0) + s.employment.slice(1).toLowerCase() : "—"}</Pil>,
            ])}
            texts={staff.map((s) => `${s.name} ${s.present_rank ?? ""}`)}
          />
        ) : <PBody><div className="sub2">No staff are recorded with {data.deptName} as their home department. Staff records are set by HR when the establishment is imported or a staff member is added.</div></PBody>}
      </Panel>
    </>
  );
}
