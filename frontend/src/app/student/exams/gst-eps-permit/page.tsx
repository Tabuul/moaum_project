import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import { permitShown, type PermitState } from "@/lib/gst-eps-permit";
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
  let r = await api<PermitState>(`/api/v1/me/gst-eps-permit${asked ? `?semester=${asked}` : ""}`);
  // V728: no semester asked and the open one shows nothing — no GST or EPS course, none waiting on a draft, no permit — but an
  // earlier semester's registration holds some (a carry-over added in the first semester): that semester's permit is the one shown.
  // A draft holding GST or EPS courses stays in view, with its reason, so it is submitted
  const other = r.ok && !asked && !permitShown(r.data) ? r.data.otherSemesters ?? [] : [];
  if (other.length) {
    const there = await api<PermitState>(`/api/v1/me/gst-eps-permit?semester=${other[other.length - 1]}`);
    if (there.ok) r = there;
  }
  // the semesters of the session up to the open one: the student may print an earlier semester's permit of the same session
  const open = r.ok ? (r.data.openSemester ?? r.data.semester) : 1;
  const semesters = Array.from({ length: Math.max(1, Math.min(3, open)) }, (_, i) => i + 1);
  return (
    <Shell route="s/gstpermit" me={loaded.me} sub={r.ok ? `${r.data.session} · ${semesterName(r.data.semester)} semester` : undefined}>
      {r.ok ? <GstEpsPermit v={r.data} semesters={semesters} /> : <ProblemNotice problem={r.problem} />}
    </Shell>
  );
}
