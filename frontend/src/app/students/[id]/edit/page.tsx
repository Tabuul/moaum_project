import { api } from "@/lib/api";
import type { StudentRecord } from "@/lib/student";
import type { EditPage } from "@/lib/student-edit";
import type { Faculty } from "@/lib/programme-swap";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { StudentEdit } from "./StudentEdit";

export const dynamic = "force-dynamic";

/** /students/[id]/edit — V642: the Academic Office student edit page; ?section= opens a section */
export default async function StudentEditPage({ params, searchParams }: {
  params: Promise<{ id: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const { id } = await params;
  const sp = await searchParams;
  const [me, page, record, structure] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<EditPage>(`/api/v1/student/students/${id}/edit`),
    api<StudentRecord>(`/api/v1/student/students/${id}`),
    api<{ faculties: Faculty[] }>("/api/v1/programme-swaps/structure"),
  ]);
  return (
    <Shell route="t/studentedit" me={me.ok ? me.data : null}>
      {page.ok ? (
        <StudentEdit page={page.data} record={record.ok ? record.data : null} faculties={structure.ok ? structure.data.faculties : []}
          actingOffice={me.ok ? me.data.activeOffice ?? null : null} initialSection={typeof sp.section === "string" ? sp.section : null} />
      ) : <ProblemNotice problem={page.problem} />}
    </Shell>
  );
}
