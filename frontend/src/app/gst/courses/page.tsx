import { api } from "@/lib/api";
import { Shell, type Me } from "@/components/proto/Shell";
import { ProblemNotice } from "@/components/ProblemNotice";
import { GstCourses, type GstCoursesData } from "@/app/gst/GstCourses";

export const dynamic = "force-dynamic";

/** t/gstcourses — the GST office's courses (V314): the catalogue, the session's offerings with their registrations and sheets, the lecturers */
export default async function GSTCoursesPage({ searchParams }: { searchParams: Promise<Record<string, string | string[] | undefined>> }) {
  const p = await searchParams;
  const session = typeof p.session === "string" && /^\d{4}\/\d{4}$/.test(p.session) ? p.session : "";
  const semester = p.semester === "1" || p.semester === "2" || p.semester === "3" ? p.semester : "";
  const q = new URLSearchParams();
  if (session) q.set("session", session);
  if (semester) q.set("semester", semester);
  const [me, data] = await Promise.all([api<Me>("/api/v1/iam/me"), api<GstCoursesData>(`/api/v1/gst/GST/courses?${q.toString()}`)]);
  return (
    <Shell route="t/gstcourses" me={me.ok ? me.data : null}>
      {data.ok ? <GstCourses data={data.data} base="/gst" actingOffice={me.ok ? me.data.activeOffice : null} /> : <ProblemNotice problem={data.problem} />}
    </Shell>
  );
}
