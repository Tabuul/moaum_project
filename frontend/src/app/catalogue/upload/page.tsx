import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { Courses } from "./Courses";

export const dynamic = "force-dynamic";

interface ProgrammeOption { code: string; name: string; facultyName?: string }

/** t/courseupload — load a department's CCMAS course structure. */
export default async function CourseUploadPage() {
  const [me, progs] = await Promise.all([
    api<Me>("/api/v1/iam/me"),
    api<ProgrammeOption[]>("/api/v1/admissions/programmes"),
  ]);
  return (
    <Shell route="t/courseupload" me={me.ok ? me.data : null}>
      <Courses programmes={progs.ok ? progs.data : []} actingOffice={me.ok ? me.data.activeOffice : null} />
    </Shell>
  );
}
