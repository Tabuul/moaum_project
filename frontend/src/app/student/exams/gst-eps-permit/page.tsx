import { Shell } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { api } from "@/lib/api";
import { permitSemesterName, permitShown, type PermitState } from "@/lib/gst-eps-permit";
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
  // V754: the Summer is never the open semester (it is no policy.semester), so semester 3 is offered past it when its state is the
  // session's Summer with GST or EPS courses to show — read here unless it is the one shown
  const third = r.ok && open < 3 && r.data.semester !== 3 ? await api<PermitState>("/api/v1/me/gst-eps-permit?semester=3") : null;
  const s3 = r.ok && r.data.semester === 3 ? r.data : third?.ok ? third.data : null;
  if (s3?.summer && permitShown(s3) && !semesters.includes(3)) semesters.push(3);
  return (
    <Shell route="s/gstpermit" me={loaded.me} sub={r.ok ? `${r.data.session} · ${permitSemesterName(r.data.semester, r.data.summer)} semester` : undefined}>
      {r.ok ? <GstEpsPermit v={r.data} semesters={semesters} summer={!!s3?.summer} /> : <ProblemNotice problem={r.problem} />}
    </Shell>
  );
}
