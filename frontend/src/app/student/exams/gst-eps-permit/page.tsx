import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import type { PermitState } from "@/lib/gst-eps-permit";
import { semesterName } from "@/lib/student-portal";
import { loadStudent } from "../../load";
import { GstEpsPermit } from "./GstEpsPermit";

export const dynamic = "force-dynamic";

/** s/gstpermit — the student's GST & EPS examination permit (V492): the semester's own, the open one by default */
export default async function Page({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const loaded = await loadStudent();
  if (!loaded.student) return <Shell route="s/gstpermit" me={loaded.me}><ProblemNotice problem={loaded.problem} /></Shell>;
  const sp = await searchParams;
  const asked = typeof sp.semester === "string" && /^[123]$/.test(sp.semester) ? sp.semester : null;
  const r = await api<PermitState>(`/api/v1/me/gst-eps-permit${asked ? `?semester=${asked}` : ""}`);
  // the semesters of the session up to the open one: the student may print an earlier semester's permit of the same session
  const open = r.ok ? (r.data.openSemester ?? r.data.semester) : 1;
  const semesters = Array.from({ length: Math.max(1, Math.min(3, open)) }, (_, i) => i + 1);
  return (
    <Shell route="s/gstpermit" me={loaded.me} sub={r.ok ? `${r.data.session} · ${semesterName(r.data.semester)} semester` : undefined}>
      {r.ok ? <GstEpsPermit v={r.data} semesters={semesters} /> : <ProblemNotice problem={r.problem} />}
    </Shell>
  );
}
